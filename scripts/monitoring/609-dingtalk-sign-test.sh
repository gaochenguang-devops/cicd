#!/bin/bash
set -uo pipefail
URL='__DINGTALK_WEBHOOK_URL__'
SEC='__DINGTALK_SECRET__'

echo "=== 1. 写入加签密钥并重启 bridge ==="
kubectl -n monitoring create secret generic dingtalk-bot \
  --from-literal=webhook-url="$URL" \
  --from-literal=secret="$SEC" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring rollout restart deploy/dingtalk-bridge >/dev/null
kubectl -n monitoring rollout status deploy/dingtalk-bridge --timeout=90s | tail -1
kubectl -n monitoring exec deploy/dingtalk-bridge -- python -c 'import urllib.request;print("  healthz:",urllib.request.urlopen("http://localhost:8080/healthz").read().decode())'

echo "=== 2. 通道自测（bridge 直连 → 钉钉群） ==="
JSON='{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"DingTalkChannelTest","severity":"warning","instance":"channel-selftest","namespace":"monitoring"},"annotations":{"summary":"钉钉通道自测（可忽略）","description":"签名已配置，本条用于验证送达，不需要任何处理。"},"startsAt":"2026-11-27T00:00:00Z"}]}'
kubectl -n monitoring exec deploy/grafana -- curl -s -m 20 -X POST \
  -H 'Content-Type: application/json' -d "$JSON" \
  http://dingtalk-bridge.monitoring.svc.cluster.local:8080/webhook 2>&1 | tail -2
sleep 2
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=4 2>&1 | tail -4

echo "=== 3. 全链路：amtool 注入 warning 告警 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname=AlertPipelineTest severity=warning namespace=monitoring \
  instance=amtool-selftest summary="告警链路联调（可忽略）" \
  description="由 amtool 注入：Prometheus 规则 → Alertmanager → bridge → 钉钉群 全链路验证。" --duration=4m 2>&1 | tail -3

echo "=== 4. 等待 group_wait(30s) + 送达 ==="
sleep 45
echo "--- AM 侧告警状态 ---"
curl -s http://10.103.87.112:9093/api/v2/alerts -o /tmp/am.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/am.json"))
for a in d:
    print("  %-26s %-8s %s" % (a["labels"].get("alertname"), a["labels"].get("severity"), a["status"]["state"]))
print("  共", len(d), "条")
PY
echo "--- bridge 日志（钉钉 errcode） ---"
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=12 2>&1 | tail -12

echo "=== 5. 触发恢复：清掉测试告警，再看恢复消息 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert resolve alertname=AlertPipelineTest 2>&1 | tail -2
sleep 30
echo "--- 恢复后的 bridge 日志 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=10 2>&1 | tail -10
echo "=== 6. 剩余告警 ==="
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin); print("  共",len(d),"条", [a["labels"].get("alertname") for a in d])
'

