#!/bin/bash
set -uo pipefail
echo "=== 服务器时间 ==="
date -u '+%Y-%m-%dT%H:%M:%S UTC'
echo "=== 等 100s（越过 endsAt） ==="
sleep 100
date -u '+%Y-%m-%dT%H:%M:%S UTC'
echo "--- bridge 投递记录 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -E 'resp|listening'
echo "--- 成功条数 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c 'errcode":0'
echo "--- AM 告警 ---"
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  ",a["labels"]["alertname"],a["status"]["state"])
print("  共",len(d))
'

