#!/usr/bin/env bash
set -uo pipefail
P=$(kubectl -n kube-system get pod -l k8s-app=metrics-server --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "pod=$P"
kubectl -n kube-system logs "$P" --tail=10
echo "--- describe 尾 ---"
kubectl -n kube-system describe pod "$P" | tail -10
echo "--- 实际 args ---"
kubectl -n kube-system get pod "$P" -o jsonpath='{.spec.containers[0].args}{"\n"}{.spec.containers[0].volumeMounts}{"\n"}'
