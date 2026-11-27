#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" 2>/dev/null || true

echo "=== 1. 准备存储目录 ==="
mkdir -p /data/monitoring/prometheus /data/monitoring/alertmanager
chown -R 65534:65534 /data/monitoring/prometheus /data/monitoring/alertmanager
df -h /data | tail -1

echo "=== 2. 网关 basic auth（prometheus / alertmanager 控制台） ==="
HASH=$(openssl passwd -apr1 '__GATEWAY_BASIC_PASS__')
kubectl -n gateway create secret generic gateway-basic-auth \
  --from-literal=htpasswd="monitoring:${HASH}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway get secret gateway-basic-auth -o jsonpath='{.data.htpasswd}' | base64 -d; echo

echo "=== 3. 应用网关新配置（含 prom/alert 站点 + 直连宿主 IP） ==="
kubectl apply -f /root/gw-manifests/20-nginx-config.yaml
kubectl apply -f /root/gw-manifests/30-deployment-service.yaml
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=150s

echo "=== 4. 部署监控组件 ==="
kubectl apply -f /root/gw-manifests/monitoring/
kubectl -n monitoring rollout status deploy/kube-state-metrics --timeout=150s
kubectl -n monitoring rollout status ds/node-exporter --timeout=150s
kubectl -n monitoring rollout status deploy/prometheus --timeout=200s
kubectl -n monitoring rollout status deploy/alertmanager --timeout=150s
kubectl -n monitoring rollout status deploy/wechat-bridge --timeout=150s || true

echo "=== 5. 运行状态 ==="
kubectl -n monitoring get pods -o wide
