#!/usr/bin/env bash
set -uo pipefail
PAT="__GITLAB_PAT__"
cd /tmp/podinfo-src && git pull -q origin main
mkdir -p deploy/webapp
install -m644 /tmp/in/webapp-kustomization.yaml deploy/webapp/kustomization.yaml
install -m644 /tmp/in/webapp-application.yaml deploy/webapp/application.yaml
install -m644 /tmp/in/gitlab-ci.yml ./.gitlab-ci.yml
git add -A deploy/webapp .gitlab-ci.yml
git -c user.email=dev@local -c user.name=Developer commit -q -m "feat(webapp): 三层 webapp 部署 + CI 同步回写" || echo "  无变更"
git push -q origin main
echo "  HEAD=$(git rev-parse --short HEAD)"
echo
echo "== 校验 kustomize 渲染 =="
kubectl kustomize deploy/webapp 2>&1 | grep -E "^kind: |image:|nodePort|target:" | head -20 || echo "  kustomize 校验失败"
