#!/bin/bash
set -uo pipefail
echo "=== 1) nginx 镜像转存到 Harbor library ==="
podman pull -q docker.m.daocloud.io/library/nginx:1.27-alpine >/dev/null 2>&1 && echo "  pull ok"
podman tag docker.m.daocloud.io/library/nginx:1.27-alpine 192.168.200.12:30090/library/nginx:1.27-alpine
podman push -q --creds admin:__HARBOR_ADMIN_PASS__ --tls-verify=false 192.168.200.12:30090/library/nginx:1.27-alpine >/dev/null 2>&1 \
  && echo "  push ok" || echo "  push FAIL"

echo "=== 2) 命名空间 + 宿主机后端 Service/Endpoints ==="
kubectl apply -f /root/gw-manifests/00-namespace-host-endpoints.yaml

echo "=== 3) TLS Secret（来自 /root/gateway-tls） ==="
kubectl -n gateway create secret tls gateway-tls \
  --cert=/root/gateway-tls/gateway.crt --key=/root/gateway-tls/gateway.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway get secret gateway-tls -o jsonpath='{.type}'; echo

echo "=== 4) 配置 + 工作负载 + LB Service ==="
kubectl apply -f /root/gw-manifests/20-nginx-config.yaml
kubectl apply -f /root/gw-manifests/30-deployment-service.yaml

echo "=== 5) 等待就绪 ==="
kubectl -n gateway rollout status deploy/gateway --timeout=180s
kubectl -n gateway get pods -o wide
kubectl -n gateway get svc gateway -o wide
