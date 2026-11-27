#!/bin/bash
set -uo pipefail
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'
sleep 45
echo "=== Prometheus 日志中的规则/配置错误 ==="
kubectl -n monitoring logs deploy/prometheus --tail=40 | grep -iE 'error|warn|rule' | head -10 || echo "  无"
echo "=== 规则列表 ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/rules?type=alert' \
 | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  status:", d["status"])
for g in d["data"]["groups"]:
    print("  %s -> %s" % (g["name"], ",".join(r["name"] for r in g["rules"])))
'
echo "=== 目标健康（再看一次） ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/targets?state=active' \
 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for t in d["data"]["activeTargets"]:
    print("  %-28s %s" % (t["labels"]["job"], t["health"]))
'
echo "=== 关键指标抽查 ==="
for q in 'count(kube_pod_info)' 'node_filesystem_avail_bytes{mountpoint="/"}' 'count(up==1)'; do
  v=$(curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP --get --data-urlencode "query=$q" 'https://prometheus.corp.local/api/v1/query' \
      | python3 -c 'import json,sys;d=json.load(sys.stdin);r=d["data"]["result"];print(r[0]["value"][1] if r else "EMPTY")')
  echo "  $q => $v"
done
