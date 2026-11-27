#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
echo "== 远端 kustomization =="
cd /tmp/podinfo-src && git fetch -q origin main && git show origin/main:deploy/podinfo/kustomization.yaml | grep -A2 podinfo-image
echo
echo "== GitLab 项目可见性 =="
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2" | jq -r '"  \(.path_with_namespace) visibility=\(.visibility) default=\(.default_branch)"'
echo
echo "== ArgoCD 已配置仓库 =="
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository -o json 2>/dev/null \
  | jq -r '.items[]? | "  \(.data.url|@base64d) type=\(.data.type|@base64d) user=\(.data.username|@base64d? // "-")"' || echo "  (无)"
echo
echo "== ArgoCD 现有应用 =="
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,REPO:.spec.source.repoURL,PATH:.spec.source.path,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null
echo
echo "== 旧 demo 的 repo 配置 (对比用) =="
kubectl -n argocd get applications demo-app -o jsonpath='{.spec.source.repoURL}{"\n"}' 2>/dev/null
