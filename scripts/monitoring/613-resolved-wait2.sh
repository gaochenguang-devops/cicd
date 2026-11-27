#!/bin/bash
set -uo pipefail
echo "=== 再等 150s（确保越过 endsAt 06:21:02） ==="
sleep 150
date -u '+%Y-%m-%dT%H:%M:%S UTC'
echo "--- bridge 投递记录 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -E 'resp'
echo "--- 成功条数 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c 'errcode":0'
echo "--- AM 告警 ---"
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  ",a["labels"]["alertname"],a["status"]["state"],a.get("endsAt"))
print("  共",len(d))
'
echo "--- AM 最近通知日志 ---"
kubectl -n monitoring logs deploy/alertmanager --tail=40 2>&1 | grep -iE 'notify|dingtalk|error' | tail -6

