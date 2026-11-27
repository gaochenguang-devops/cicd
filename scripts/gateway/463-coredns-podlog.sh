#!/bin/bash
set -uo pipefail
P=$(kubectl -n kube-system get pod -l k8s-app=kube-dns -o name | grep -v 76fcc | head -1)
echo "=== $P describe 尾部 ==="
kubectl -n kube-system describe $P 2>&1 | tail -25
echo "=== 该 Pod 日志（含退出信息） ==="
kubectl -n kube-system logs $P --previous 2>&1 | tail -20
echo "=== 该 Pod 当前日志 ==="
kubectl -n kube-system logs $P 2>&1 | tail -10
