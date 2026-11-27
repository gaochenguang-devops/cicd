#!/usr/bin/env bash
set -uo pipefail
P=$(kubectl -n kube-system get pod -l k8s-app=metrics-server --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
echo "pod=$P"
kubectl -n kube-system logs "$P" --tail=6
echo "--- events ---"
kubectl -n kube-system describe pod "$P" | grep -A4 "Events:" | tail -6
echo "--- endpoints ---"
kubectl -n kube-system get endpoints metrics-server 2>/dev/null
echo "--- 容器内端口探测 ---"
kubectl -n kube-system exec "$P" -- /metrics-server --help >/dev/null 2>&1 && echo "exec ok" || true
echo "--- 直接访问 svc ---"
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" 2>&1 | head -c 200; echo
