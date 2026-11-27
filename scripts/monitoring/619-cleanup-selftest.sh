#!/bin/bash
set -uo pipefail
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert resolve alertname=SelfTestRule 2>&1 | tail -2
sleep 35
echo "--- AM 告警 ---"
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin); print("  剩余:",len(d),[a["labels"]["alertname"] for a in d])
'
echo "--- bridge 投递 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c 'errcode":0'

