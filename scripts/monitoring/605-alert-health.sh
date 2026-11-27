#!/bin/bash
set -uo pipefail
echo "=== 规则评估是否有错误 ==="
kubectl -n monitoring logs deploy/prometheus --tail=20 2>&1 | grep -iE 'error|rule' | tail -5 || echo "  无规则错误"
echo "=== 当前活跃告警（应为空或极少） ==="
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  ",a["labels"].get("alertname"),a["labels"].get("severity"),a["status"]["state"])
print("  共",len(d),"条")
'
echo "=== 各 Pod 状态 ==="
kubectl -n monitoring get pods --no-headers | awk '{print "  "$1, $3}'

