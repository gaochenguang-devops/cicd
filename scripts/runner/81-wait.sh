#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
PIPE=$(cat /root/podinfo-pipeline.id)
echo "polling pipeline $PIPE ..."
for i in $(seq 1 60); do
  ST=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r .status)
  printf "  [%02d] %s\n" "$i" "$ST"
  case "$ST" in success|failed|canceled|skipped) break;; esac
  sleep 10
done
echo
echo "== jobs =="
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  \(.name) \(.status) dur=\((.duration // 0)|floor)s"'
echo
echo "== 失败的 trace 尾部 =="
for J in $(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | select(.status=="failed") | .id'); do
  echo "-- job $J --"
  curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/jobs/$J/trace" | tail -25
done
echo
echo "== Harbor 中的 podinfo 镜像 =="
curl -s -u "admin:__HARBOR_ADMIN_PASS__" "$GL:30090/api/v2.0/projects/apps/repositories/podinfo/artifacts?page_size=5" \
  | jq -r '.[]? | "  \(.tags[0].name)  \(.size/1048576|floor)MB  \(.push_time)"' 2>/dev/null || echo "  (查询失败)"
