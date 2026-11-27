#!/bin/bash
set -uo pipefail
POD=$(kubectl -n gateway get pods -o jsonpath='{.items[0].metadata.name}')
echo "=== 从网关 Pod 测宿主机端口 ==="
kubectl -n gateway exec "$POD" -- sh -c 'command -v nc >/dev/null || (apk add --no-cache busybox >/dev/null 2>&1 || true); for p in 80 389 8090; do (nc -z -w2 192.168.200.12 $p && echo "  :$p open") || echo "  :$p closed"; done'
