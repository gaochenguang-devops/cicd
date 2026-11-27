#!/usr/bin/env bash
set -uo pipefail
echo "== ArgoCD 资源健康明细（非 Healthy 项）=="
kubectl -n argocd get app podinfo -o json \
  | jq -r '.status.resources[] | select(.health.status != "Healthy") | "  \(.kind)/\(.name) health=\(.health.status) msg=\(.health.message // "-")"'
echo
echo "== conditions =="
kubectl -n argocd get app podinfo -o json | jq -r '.status.conditions[]? | "  \(.type) \(.message)"'
echo
echo "== HPA / PDB 状态 =="
kubectl -n podinfo get hpa,pdb 2>/dev/null
echo
echo "== 是否有 metrics-server =="
kubectl get apiservice v1beta1.metrics.k8s.io 2>/dev/null || echo "  未安装 metrics-server"
