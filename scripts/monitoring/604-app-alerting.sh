#!/bin/bash
set -uo pipefail
echo "=== 1. 重新应用钉钉桥接 ==="
kubectl apply -f /root/gw-manifests/monitoring-43-dingtalk-bridge.yaml
echo "=== 2. 重新应用 Alertmanager 路由 ==="
kubectl apply -f /root/gw-manifests/monitoring-40-alertmanager.yaml
kubectl -n monitoring rollout restart deploy/alertmanager >/dev/null
kubectl -n monitoring rollout status deploy/alertmanager --timeout=90s | tail -1
echo "=== 3. CM 里是否真的是钉钉路由 ==="
kubectl -n monitoring get cm alertmanager-config -o jsonpath='{.data.alertmanager\.yml}' | grep -nE 'dingtalk|receiver:' | head -8
echo "=== 4. 生效配置（amtool 视角） ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 config show 2>/dev/null | sed -n '/route:/,/receivers:/p' | head -20
echo "=== 5. bridge 健康 + 是否读到 webhook ==="
kubectl -n monitoring get pods -l app=dingtalk-bridge --no-headers
kubectl -n monitoring exec deploy/dingtalk-bridge -- python -c 'import urllib.request;print("  healthz:",urllib.request.urlopen("http://localhost:8080/healthz").read().decode())' 2>&1 | tail -2

