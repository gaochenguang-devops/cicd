#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"
PAT="__GITLAB_PAT__"
echo "== 上次创建 runner 的响应 =="
cat /tmp/runner.json | head -c 300; echo
echo
echo "== 用 user/runners（admin）重试 =="
curl -s -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' -o /tmp/runner2.json -w "  http=%{http_code}\n" \
  -X POST "$GL/api/v4/user/runners" \
  -d '{"runner_type":"project_type","project_id":2,"description":"podinfo-shell-podman","tag_list":["podinfo","shell"],"run_untagged":true,"locked":false}'
cat /tmp/runner2.json | head -c 400; echo
RTOKEN=$(jq -r '.token // empty' /tmp/runner2.json); RID=$(jq -r '.id // empty' /tmp/runner2.json)
if [ -n "$RTOKEN" ]; then
  echo "  runner id=$RID token=${RTOKEN:0:14}..."
  gitlab-runner register --non-interactive --url "$GL/" --token "$RTOKEN" \
    --executor shell --description "podinfo-shell-podman" 2>&1 | tail -3
  systemctl restart gitlab-runner
  sleep 6
  curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/runners" | jq -r '.[] | "  runner=\(.description) online=\(.online) status=\(.status) executor=\(.executor)"'
fi
echo
echo "== 本地 runner 状态 =="
systemctl is-active gitlab-runner
gitlab-runner list 2>&1 | tail -3
