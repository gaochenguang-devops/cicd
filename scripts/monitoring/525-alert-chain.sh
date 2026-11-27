#!/bin/bash
set -uo pipefail
echo "=== 注入 critical 告警，验证 AM → 企业微信桥接 链路 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname="ChainSmokeTest" severity=critical instance="chain-test" \
  --annotation description="验证 Alertmanager→wechat-bridge 转换链路" 2>&1 | tail -2
sleep 45
echo "=== 桥接日志（应看到渲染后的中文文本） ==="
kubectl -n monitoring logs deploy/wechat-bridge --tail=15 | tail -8
echo "=== 清理测试告警 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert resolve alertname="ChainSmokeTest" instance="chain-test" 2>&1 | tail -1
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert resolve alertname="SmokeTest" instance="smoke-1" 2>&1 | tail -1
