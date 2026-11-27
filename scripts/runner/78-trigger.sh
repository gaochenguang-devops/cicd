#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
echo "== 已有流水线 =="
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines" | jq -r '.[] | "  \(.id) status=\(.status) ref=\(.ref) sha=\(.sha[0:7])"' | head -5
echo
echo "== 用 JSON 触发 =="
curl -s -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' -o /tmp/pipe.json -w "  http=%{http_code}\n" \
  -X POST "$GL/api/v4/projects/2/pipeline" -d '{"ref":"main"}'
head -c 300 /tmp/pipe.json; echo
PIPE=$(jq -r '.id // empty' /tmp/pipe.json)
if [ -n "$PIPE" ]; then
  echo "$PIPE" > /root/podinfo-pipeline.id
  sleep 12
  curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r '"  status=\(.status) sha=\(.sha[0:7])"'
  curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name) stage=\(.stage) status=\(.status)"'
fi
