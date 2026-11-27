#!/bin/bash
set -uo pipefail
echo "=== 当前 AM 告警状态（看是否已 resolved） ==="
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  %-20s state=%s  startsAt=%s endsAt=%s" % (a["labels"]["alertname"], a["status"]["state"], a["startsAt"][:19], (a.get("endsAt") or "-")[:19]))
print("  共",len(d))
'
echo "=== 再等 60s 看恢复消息是否发出 ==="
sleep 60
echo "--- bridge 全部投递记录 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -E 'resp|listening'
echo "--- 成功次数 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c '"errcode":0'
echo "=== AM 通知记录（最近 5 条） ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert query AlertPipelineTest 2>&1 | tail -6
echo "=== AM 日志中该告警的投递结果 ==="
kubectl -n monitoring logs deploy/alertmanager --tail=30 2>&1 | grep -iE 'dingtalk|notify|error' | tail -8

