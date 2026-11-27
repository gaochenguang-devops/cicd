#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
T0=$(date +%s)
cd /tmp/podinfo-src
git fetch -q origin main && git reset -q --hard origin/main
SHAF=$(git rev-parse HEAD); SHA=${SHAF:0:8}
echo "当前 HEAD=$SHA  提交=$(git log -1 --format=%s)"

echo "== 查找该 commit 的流水线 =="
PIPE=""
for i in $(seq 1 15); do
  PIPE=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines?sha=$SHAF" | jq -r '.[0].id // empty')
  [ -n "$PIPE" ] && break; sleep 5
done
if [ -z "$PIPE" ]; then
  echo "  未找到流水线，手动触发"; curl -s -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' -X POST "$GL/api/v4/projects/2/pipeline" -d '{"ref":"main"}' >/dev/null
  sleep 5
  PIPE=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines?sha=$SHAF" | jq -r '.[0].id // empty')
fi
echo "  pipeline=$PIPE"

for i in $(seq 1 100); do
  ST=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r .status)
  case "$ST" in success|failed|canceled|skipped) break;; esac
  sleep 5
done
echo "  status=$ST  t=+$(( $(date +%s) - T0 ))s"
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name) \(.status) \((.duration // 0)|floor)s"'
[ "$ST" = success ] || exit 1

echo "== 等 ArgoCD 上线新镜像 =="
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null
for i in $(seq 1 70); do
  IMG=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}')
  READY=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.status.readyReplicas}')
  HEALTH=$(kubectl -n argocd get app podinfo -o jsonpath='{.status.health.status}')
  echo "  [$i] image=${IMG##*:} ready=$READY health=$HEALTH t=+$(( $(date +%s) - T0 ))s"
  case "$IMG" in *:$SHAF) [ "$READY" = "2" ] && break;; esac
  # 2026-11-26：流水线改为推全 40 位 sha，这里必须比对 SHAF 而不是 8 位 SHA，否则永远等不到
  sleep 5
done

echo "== 运行态 =="
kubectl -n podinfo get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,IMAGE:.spec.containers[0].image
echo
curl -s -m 5 http://192.168.200.12:30095/version; echo
echo "总耗时 +$(( $(date +%s) - T0 ))s"
