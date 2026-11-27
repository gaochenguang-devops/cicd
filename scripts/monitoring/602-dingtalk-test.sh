#!/bin/bash
set -uo pipefail
echo "=== 钉钉桥接 → 真实群机器人 直连自测（先确认 webhook 已配） ==="
kubectl -n monitoring exec deploy/dingtalk-bridge -- python - <<'PY'
import json, os, urllib.request
URL = os.environ.get("DINGTALK_WEBHOOK_URL", "")
print("  webhook 是否已配置:", bool(URL))
payload = {
  "status": "firing",
  "alerts": [{
    "status": "firing",
    "labels": {"alertname": "DingTalkChannelTest", "severity": "warning",
               "instance": "channel-selftest", "namespace": "monitoring"},
    "annotations": {"summary": "钉钉通道自测（可忽略）",
                    "description": "这是 601 部署完成后的一次链路自测，不需要任何处理。"},
    "startsAt": "2026-11-27T00:00:00Z"
  }]
}
req = urllib.request.Request("http://localhost:8080/webhook",
      data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
print("  bridge 返回:", urllib.request.urlopen(req, timeout=10).read().decode())
PY
echo "=== 走完整链路：amtool 注入一条真实告警，等 Alertmanager 发给钉钉 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname=AlertPipelineTest severity=warning namespace=monitoring \
  instance=amtool-selftest summary="告警链路联调（可忽略）" \
  description="由 amtool 注入，用于验证 Prometheus→AM→bridge→钉钉 全链路。" --duration=3m 2>&1 | tail -3
sleep 15
echo "=== AM 侧当前告警 ==="
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  %-24s %-10s %s" % (a["labels"].get("alertname"), a["labels"].get("severity"), a["status"]["state"]))
print("  共", len(d), "条")
'
echo "=== bridge 侧日志（看钉钉返回 errcode） ==="
kubectl -n monitoring logs deploy/dingtalk-bridge --tail=15 2>&1 | tail -15
echo "=== 清掉测试告警 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert resolve alertname=AlertPipelineTest 2>&1 | tail -2

