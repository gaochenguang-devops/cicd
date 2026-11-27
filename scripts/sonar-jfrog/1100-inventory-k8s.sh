#!/usr/bin/env bash
set -uo pipefail
echo "===== K8s 命名空间 ====="
kubectl get ns --no-headers | awk '{print $1, $3}'
echo
echo "===== 所有 Pod（按 ns 分组） ====="
kubectl get pod -A -o wide --no-headers | awk '{printf "%-22s %-52s %-12s %-40s %s\n", $1, $2, $3, $6, $7}' | sort
echo
echo "===== 所有 Service 类型与 NodePort ====="
kubectl get svc -A --no-headers | awk '{print $1, $2, $3, $4}' | grep -E 'NodePort|LoadBalancer' || true
echo
echo "===== Ingress ====="
kubectl get ingress -A 2>/dev/null || echo "(none)"
echo
echo "===== Deployment 副本 ====="
kubectl get deploy -A --no-headers | awk '{print $1, $2, $3"/"$4}'
echo
echo "===== StatefulSet / PVC ====="
kubectl get sts -A --no-headers 2>/dev/null || echo "(none)"
kubectl get pvc -A --no-headers 2>/dev/null || echo "(none)"
echo
echo "===== 存储类 ====="
kubectl get sc 2>/dev/null || true
