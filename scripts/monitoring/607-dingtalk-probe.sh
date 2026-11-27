#!/bin/bash
set -uo pipefail
echo "=== 新 Pod 与日志 ==="
kubectl -n monitoring get pods -l app=dingtalk-bridge -o wide --no-headers
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=6 2>&1 | tail -6

echo "=== 从 grafana Pod 发一条测试载荷给 bridge（grafana 镜像自带 curl） ==="
JSON='{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"DingTalkChannelTest","severity":"warning","instance":"channel-selftest","namespace":"monitoring"},"annotations":{"summary":"钉钉通道自测（可忽略）","description":"这是链路自测消息，不需要任何处理。"},"startsAt":"2026-11-27T00:00:00Z"}]}'
kubectl -n monitoring exec deploy/grafana -- curl -s -m 20 -X POST \
  -H 'Content-Type: application/json' \
  -d "$JSON" \
  http://dingtalk-bridge.monitoring.svc.cluster.local:8080/webhook 2>&1 | tail -3

echo
echo "=== bridge 到底回了什么（含钉钉 errcode） ==="
sleep 2
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=8 2>&1 | tail -8

