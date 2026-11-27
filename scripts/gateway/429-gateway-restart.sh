#!/bin/bash
set -uo pipefail
echo "=== 网关重启原因 ==="
kubectl -n gateway describe pod gateway-6658684d85-4fcs7 | grep -A6 'Last State' | head -10
kubectl -n gateway describe pod gateway-6658684d85-4fcs7 | grep -A8 'Events' | head -12
echo "=== 当前容器日志（重启前后） ==="
kubectl -n gateway logs deploy/gateway --tail=25
echo "=== 前一次容器日志 ==="
kubectl -n gateway logs deploy/gateway --previous --tail=15 2>/dev/null || echo "  无 previous"
echo "=== 内存/节点压力 ==="
free -g | head -2
kubectl top pods -n gateway 2>/dev/null || echo "  top 不可用"
echo "=== 触发告警的 Pod（PodCrashLooping） ==="
curl -s -k -u monitoring:__GATEWAY_BASIC_PASS__ --resolve alertmanager.corp.local:443:192.168.200.210 \
  'https://alertmanager.corp.local/api/v2/alerts' | python3 -c '
import json,sys
for a in json.load(sys.stdin): print("  ", a["labels"].get("alertname"), a["labels"].get("namespace"), a["labels"].get("pod"), "|", a.get("annotations",{}).get("description","")[:60])
'
