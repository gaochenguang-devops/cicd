#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
T0=$(date +%s)

echo "== 1. 模拟开发者提交 =="
cd /tmp/podinfo-src
git pull -q origin main
echo "" >> README.md
echo "<!-- CI/CD verified $(date -Iseconds) -->" >> README.md
git add README.md
git -c user.email=dev@local -c user.name=Developer commit -q -m "docs: trigger e2e pipeline"
git push -q origin main
SHA=$(git rev-parse --short HEAD)
echo "  commit=$SHA  t=+$(( $(date +%s) - T0 ))s"

echo "== 2. 等待流水线 =="
PIPE=""
for i in $(seq 1 20); do
  PIPE=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines?per_page=1" | jq -r '.[0].id')
  [ -n "$PIPE" ] && break; sleep 3
done
echo "  pipeline=$PIPE"
for i in $(seq 1 90); do
  ST=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r .status)
  if [ "$ST" = success ] || [ "$ST" = failed ] || [ "$ST" = canceled ]; then break; fi
  sleep 5
done
echo "  pipeline status=$ST  t=+$(( $(date +%s) - T0 ))s"
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name) \(.status) \((.duration // 0)|floor)s"'
[ "$ST" = success ] || { echo "流水线失败，终止"; exit 1; }

echo "== 3. 等 ArgoCD 同步新镜像 =="
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null
for i in $(seq 1 60); do
  IMG=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}')
  READY=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.status.readyReplicas}')
  HEALTH=$(kubectl -n argocd get app podinfo -o jsonpath='{.status.health.status}')
  echo "  [$i] image=${IMG##*:} ready=$READY health=$HEALTH t=+$(( $(date +%s) - T0 ))s"
  case "$IMG" in *:$SHA) [ "$READY" = "2" ] && break;; esac
  sleep 6
done

echo "== 4. 运行态验证 =="
kubectl -n podinfo get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image
echo
curl -s -m 5 http://192.168.200.12:30095/version; echo
curl -s -m 5 http://192.168.200.12:30095/ | head -8
echo
echo "  总耗时 +$(( $(date +%s) - T0 ))s（commit→新镜像上线）"
