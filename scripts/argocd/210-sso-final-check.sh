#!/usr/bin/env bash
set -uo pipefail
echo "===== argocd 组件 ====="
kubectl -n argocd get pods | grep -E 'dex|server|controller|repo' | sed 's/^/  /'
echo "===== 应用健康 ====="
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' | sed 's/^/  /'
echo "===== 关键配置读回 ====="
echo "  url=$(kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.url}')"
echo "  dex.config 前 3 行："
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}' | head -3 | sed 's/^/    /'
echo "  rbac default=$(kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.default}')"
echo "===== dex 是否加载 connector ====="
kubectl -n argocd logs deploy/argocd-dex-server --tail=200 | grep -c 'config connector' | sed 's/^/  connector 配置行数: /'
