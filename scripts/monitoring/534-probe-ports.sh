#!/bin/bash
set -uo pipefail
echo "=== keycloak Service 端口 ==="
kubectl -n keycloak get svc keycloak -o jsonpath='{.spec.ports}{"\n"}'
echo "=== keycloak Pod 端口 ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'
echo "=== 在 keycloak pod 里自测 /metrics（管理端口 9000） ==="
KP=$(kubectl -n keycloak get pod -o name | grep -v db | head -1)
kubectl -n keycloak exec $KP -- sh -c 'curl -s -o /dev/null -w "  9000/metrics -> %{http_code}\n" http://localhost:9000/metrics; curl -s http://localhost:9000/metrics | head -3' 2>&1 | head -6
echo "=== prometheus 容器内能否直连 keycloak pod IP:9000 ==="
kubectl -n keycloak get pod -o jsonpath='{.items[0].status.podIP}{"\n"}'
echo "=== 现有 gateway nginx 配置中的 server 块 ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' | grep -nE "server_name|listen|proxy_pass|set \\\$backend" | head -40

