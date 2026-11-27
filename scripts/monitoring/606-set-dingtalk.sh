#!/bin/bash
set -uo pipefail
URL='__DINGTALK_WEBHOOK_URL__'

echo "=== 1. 写入 Secret（当前无加签、无关键词，先探真实安全模式） ==="
kubectl -n monitoring create secret generic dingtalk-bot \
  --from-literal=webhook-url="$URL" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring get secret dingtalk-bot -o json | python3 -c '
import sys,json,base64
d=json.load(sys.stdin)["data"]
for k,v in d.items(): print("  key:",k,"->",base64.b64decode(v).decode()[:70]+"...")
'

echo "=== 2. 重启 bridge 使之读到 env ==="
kubectl -n monitoring rollout restart deploy/dingtalk-bridge >/dev/null
kubectl -n monitoring rollout status deploy/dingtalk-bridge --timeout=90s | tail -1
kubectl -n monitoring exec deploy/dingtalk-bridge -- python -c 'import urllib.request;print("  healthz:",urllib.request.urlopen("http://localhost:8080/healthz").read().decode())'

echo "=== 3. 直接打一次钉钉，看 errcode（先不经过 AM） ==="
kubectl -n monitoring exec deploy/dingtalk-bridge -- python - <<'PY'
import json, urllib.request
payload = {"status":"firing","alerts":[{"status":"firing",
 "labels":{"alertname":"DingTalkChannelTest","severity":"warning","instance":"channel-selftest","namespace":"monitoring"},
 "annotations":{"summary":"钉钉通道自测（可忽略）","description":"这是链路自测消息，无需处理。"},
 "startsAt":"2026-11-27T00:00:00Z"}]}
req = urllib.request.Request("http://localhost:8080/webhook", data=json.dumps(payload).encode(),
                             headers={"Content-Type":"application/json"})
try:
    print("  bridge 返回:", urllib.request.urlopen(req, timeout=15).read().decode())
except Exception as e:
    print("  bridge 报错:", e)
PY
echo "=== 4. bridge 日志 ==="
kubectl -n monitoring logs deploy/dingtalk-bridge --tail=10 2>&1 | tail -10

