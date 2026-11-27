#!/bin/bash
set -uo pipefail
echo "=== 从 gateway Pod（alpine busybox）解析 ==="
kubectl -n gateway exec deploy/gateway -- nslookup keycloak.corp.local 2>&1 | head -8
echo "=== 从 podinfo Pod 解析 ==="
P=$(kubectl -n podinfo get pod -o name | head -1 2>/dev/null)
echo "  $P"
kubectl -n podinfo exec $P -- nslookup gitlab.corp.local 2>&1 | head -8
echo "=== CoreDNS 最近日志 ==="
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=12 2>&1 | tail -12
echo "=== 直接对 ClusterIP 查 DNS（宿主上用 dnsutils？用 getent 不行，用 resolvectl） ==="
kubectl run dns-probe --rm -i --restart=Never --image=192.168.200.12:30090/library/python:3.11-alpine --command -- python3 -c "
import socket
for h in ['keycloak.corp.local','gitlab.corp.local']:
    try:
        print(h, socket.getaddrinfo(h,443)[0][4])
    except Exception as e:
        print(h, 'ERR', e)
" 2>&1 | tail -5
