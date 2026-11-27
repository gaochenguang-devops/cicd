#!/bin/bash
set -uo pipefail
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'
kubectl -n monitoring get pods -l app=prometheus -o wide
echo "=== 规则 ==="
curl -s -k -u "$AUTH" --resolve prometheus.corp.local:443:$VIP 'https://prometheus.corp.local/api/v1/rules?type=alert' \
 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for g in d["data"]["groups"]:
    print("  group %s:" % g["name"])
    for r in g["rules"]:
        print("    - %s [%s] state=%s" % (r["name"], r["labels"].get("severity","?"), r["state"]))
'
echo "=== 自测一条告警：把 up 强制置 0 用 amtool 推送 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname="SmokeTest" severity=warning instance="smoke-1" --annotation description="链路连通性自测" 2>&1 | tail -2
sleep 3
curl -s -k -u "$AUTH" --resolve alertmanager.corp.local:443:$VIP 'https://alertmanager.corp.local/api/v2/alerts' \
 | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  AM 中告警数:", len(d))'
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert resolve alertname="SmokeTest" instance="smoke-1" 2>&1 | tail -1
