#!/bin/bash
set -uo pipefail
echo "=== amtool alert add 支持的参数（确认正确写法） ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool alert add --help 2>&1 | grep -E '^\s+--' | head -8

echo "=== 1. 注入 warning 告警（不带 --duration，先触发再手动 resolve） ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname=AlertPipelineTest severity=warning namespace=monitoring \
  instance=amtool-selftest summary="告警链路联调（可忽略）" \
  description="amtool 注入：验证 Prometheus → Alertmanager → bridge → 钉钉群 全链路，稍后会自行恢复。" 2>&1 | tail -3

echo "=== 2. 等 group_wait 30s 后看 AM 与 bridge ==="
sleep 40
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  %-24s %-8s %s" % (a["labels"].get("alertname"), a["labels"].get("severity"), a["status"]["state"]))
print("  共",len(d),"条")
'
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=6 2>&1 | tail -6

echo "=== 3. resolve，看恢复消息 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert resolve alertname=AlertPipelineTest 2>&1 | tail -2
sleep 40
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=6 2>&1 | tail -6
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin); print("  剩余告警:",len(d), [a["labels"].get("alertname") for a in d])
'
echo "=== 4. 钉钉群投递统计（bridge resp 行数） ==="
kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c 'errcode":0'

