#!/bin/bash
set -uo pipefail
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'
echo "=== A. 入口：12 域名 ==="
for h in gitlab jenkins harbor sonar artifactory argocd keycloak ldapadmin podinfo webapp prometheus alertmanager; do
  code=$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' -u "$AUTH" --resolve $h.corp.local:443:$VIP https://$h.corp.local/)
  printf "  %-14s %s\n" "$h" "$code"
done
echo "=== B. 未知域名 421 / http→https 301 ==="
curl -s -o /dev/null -k -w '  unknown=%{http_code}\n' --resolve nope.corp.local:443:$VIP https://nope.corp.local/
curl -s -o /dev/null -w '  http=%{http_code} -> %{redirect_url}\n' --resolve harbor.corp.local:80:$VIP http://harbor.corp.local/
echo "=== C. 证书链 ==="
echo | openssl s_client -connect $VIP:443 -servername harbor.corp.local -CAfile /root/gateway-tls/ca.crt 2>/dev/null | grep 'Verify return code'
echo "=== D. 网关/监控 Pod ==="
kubectl -n gateway get pods -o wide | tail -3
kubectl -n monitoring get pods -o wide
echo "=== E. Prometheus 目标与规则 ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/targets?state=active' \
 | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  up=%d/down=%d" % (sum(1 for t in d["data"]["activeTargets"] if t["health"]=="up"), sum(1 for t in d["data"]["activeTargets"] if t["health"]!="up")))'
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/rules?type=alert' \
 | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  groups=%d rules=%d" % (len(d["data"]["groups"]), sum(len(g["rules"]) for g in d["data"]["groups"])))'
echo "=== F. 当前活跃告警（应无测试残留） ==="
curl -s -k -u "$AUTH" --resolve alertmanager.corp.local:443:$VIP 'https://alertmanager.corp.local/api/v2/alerts' \
 | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  活跃告警:", len(d));[print("   -",a["labels"].get("alertname"), a["labels"].get("severity")) for a in d]'
echo "=== G. 磁盘 ==="
df -h / | tail -1
