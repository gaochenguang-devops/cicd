#!/bin/bash
set -uo pipefail
VIP=192.168.200.210
AUTH='monitoring:__GATEWAY_BASIC_PASS__'

echo "=== Pod 状态 ==="
kubectl -n monitoring get pods -o wide

echo "=== 经网关访问控制台（带 Basic Auth） ==="
curl -s -o /dev/null -k -o /dev/null -w '  prometheus /-/healthy  %{http_code}\n' -u "$AUTH" --resolve prometheus.corp.local:443:$VIP https://prometheus.corp.local/-/healthy
curl -s -o /dev/null -k -w '  alertmanager /-/ready  %{http_code}\n' -u "$AUTH" --resolve alertmanager.corp.local:443:$VIP https://alertmanager.corp.local/-/ready
curl -s -o /dev/null -k -w '  无凭据应 401          %{http_code}\n' --resolve prometheus.corp.local:443:$VIP https://prometheus.corp.local/

echo "=== 抓取目标状态 ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP \
  'https://prometheus.corp.local/api/v1/targets?state=active' \
 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for t in d["data"]["activeTargets"]:
    print("  %-28s %-28s %s" % (t["labels"]["job"], t["scrapeUrl"].split("//")[-1], t["health"]))
'
echo "=== 已加载的告警规则 ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/rules' \
 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for g in d["data"]["groups"]:
    print("  group %s: %s" % (g["name"], ",".join(r["name"] for r in g["rules"])))
'
echo "=== Alertmanager 已加载的 receiver ==="
curl -s -k -u "$AUTH" --resolve alertmanager.corp.local:443:$VIP 'https://alertmanager.corp.local/api/v2/status' \
 | python3 -c 'import json,sys; d=json.load(sys.stdin); print("  cluster:", d["cluster"]["status"], "| uptime:", d["uptime"])' 2>/dev/null || echo "  status 解析失败"

echo "=== 企业微信桥接自测（构造一条 AM 载荷） ==="
kubectl -n monitoring run bridge-test --rm -i --restart=Never --image=192.168.200.12:30090/library/python:3.11-alpine -- \
  python -c '
import json,urllib.request
p={"status":"firing","alerts":[{"labels":{"alertname":"NodeDiskUsageHigh","severity":"warning","instance":"192.168.200.12:9100"},"annotations":{"description":"根分区 76%"}}]}
r=urllib.request.Request("http://wechat-bridge.monitoring.svc.cluster.local:8080/webhook",data=json.dumps(p).encode(),headers={"Content-Type":"application/json"})
print("  bridge http:", urllib.request.urlopen(r,timeout=5).status)' 2>&1 | tail -3
kubectl -n monitoring logs deploy/wechat-bridge --tail=3
