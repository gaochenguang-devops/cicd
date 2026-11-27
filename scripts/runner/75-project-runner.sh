#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"
PAT="__GITLAB_PAT__"
echo "== 创建 GitLab 项目 podinfo =="
curl -s -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' -o /tmp/proj.json \
  -X POST "$GL/api/v4/projects" -d '{"name":"podinfo","path":"podinfo","visibility":"internal","description":"Podinfo x Harbor x ArgoCD GitOps demo"}'
PID=$(jq -r '.id' /tmp/proj.json); echo "  project id=$PID path=$(jq -r '.path_with_namespace' /tmp/proj.json)"
echo
echo "== 导入代码并推送 =="
cd /tmp/podinfo-src
rm -rf .git
git init -q -b main
git -c user.email=ci@local -c user.name="CI Bootstrap" add -A
git -c user.email=ci@local -c user.name="CI Bootstrap" commit -q -m "import podinfo upstream (github.com/stefanprodan/podinfo)"
git remote add origin "http://root:__GITLAB_PAT__@192.168.200.12/root/podinfo.git" 2>/dev/null || git remote set-url origin "http://root:__GITLAB_PAT__@192.168.200.12/root/podinfo.git"
git push -q -u origin main
curl -s -H "PRIVATE-TOKEN: $PAT" -X PUT "$GL/api/v4/projects/$PID" -d "default_branch=main" -o /dev/null
echo "  HEAD=$(git rev-parse --short HEAD) files=$(git ls-files | wc -l)"
echo
echo "== 创建项目级 Runner 并注册 =="
curl -s -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' -o /tmp/runner.json \
  -X POST "$GL/api/v4/projects/$PID/runners" \
  -d '{"runner_type":"project_type","tag_list":["podinfo","shell"],"run_untagged":true,"locked":false,"description":"podinfo-shell-podman"}'
RTOKEN=$(jq -r '.token' /tmp/runner.json); RID=$(jq -r '.id' /tmp/runner.json)
echo "  runner id=$RID token=${RTOKEN:0:12}..."
gitlab-runner register --non-interactive \
  --url "$GL/" --token "$RTOKEN" \
  --executor shell --description "podinfo-shell-podman" 2>&1 | tail -4
systemctl restart gitlab-runner
sleep 5
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/$PID/runners" | jq -r '.[] | "  runner \(.description) online=\(.online) status=\(.status) exec=\(.executor)"'
echo
echo "== 设置 CI/CD 变量 =="
RH=$(head -1 /root/harbor-ci-creds.txt); RS=$(tail -1 /root/harbor-ci-creds.txt)
setv() {
  curl -s -H "PRIVATE-TOKEN: $PAT" -o /dev/null -w "  $1=%{http_code}\n" -X POST "$GL/api/v4/projects/$PID/variables" \
    --data-urlencode "key=$1" --data-urlencode "value=$2" -d "protected=false" -d "masked=$3"
}
curl -s -H "PRIVATE-TOKEN: $PAT" -X DELETE "$GL/api/v4/projects/$PID/variables/HARBOR_USER" -o /dev/null
curl -s -H "PRIVATE-TOKEN: $PAT" -X DELETE "$GL/api/v4/projects/$PID/variables/HARBOR_PASS" -o /dev/null
curl -s -H "PRIVATE-TOKEN: $PAT" -X DELETE "$GL/api/v4/projects/$PID/variables/HARBOR_REGISTRY" -o /dev/null
curl -s -H "PRIVATE-TOKEN: $PAT" -X DELETE "$GL/api/v4/projects/$PID/variables/GIT_PUSH_TOKEN" -o /dev/null
setv HARBOR_USER "$RH" false
setv HARBOR_PASS "$RS" true
setv HARBOR_REGISTRY "192.168.200.12:30090" false
setv GIT_PUSH_TOKEN "$PAT" true
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/$PID/variables" | jq -r '.[] | "  var \(.key) masked=\(.masked)"'
echo "PROJECT_ID=$PID" > /root/podinfo-project.env
