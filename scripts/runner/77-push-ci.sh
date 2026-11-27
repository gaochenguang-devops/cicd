#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"
PAT="__GITLAB_PAT__"
RID=$(head -1 /root/harbor-ci-creds.txt); RSC=$(tail -1 /root/harbor-ci-creds.txt)

echo "== 1. 把 redis 镜像推到 Harbor（供报告里的 redis 组件使用）=="
podman pull -q docker.m.daocloud.io/library/redis:7-alpine >/dev/null 2>&1
podman tag docker.m.daocloud.io/library/redis:7-alpine 192.168.200.12:30090/apps/redis:7-alpine
echo "$RSC" | podman login --tls-verify=false -u "$RID" --password-stdin 192.168.200.12:30090 >/dev/null 2>&1
podman push --tls-verify=false 192.168.200.12:30090/apps/redis:7-alpine 2>&1 | tail -2

echo "== 2. 写入 CI 与部署清单到仓库 =="
cd /tmp/podinfo-src
install -m644 /tmp/in/Dockerfile.ci ./Dockerfile.ci
install -m644 /tmp/in/.gitlab-ci.yml ./.gitlab-ci.yml
mkdir -p deploy/podinfo
install -m644 /tmp/in/kustomization.yaml /tmp/in/app.yaml /tmp/in/redis.yaml /tmp/in/application.yaml deploy/podinfo/
ls -R deploy
echo
echo "== 3. 提交并推送（触发 CI）=="
git add Dockerfile.ci .gitlab-ci.yml deploy
git -c user.email=ci@local -c user.name="CI Bootstrap" commit -q -m "feat(ci): Harbor build pipeline + GitOps manifests"
git push -q origin main
NEW=$(git rev-parse HEAD)
echo "  pushed ${NEW:0:7}"
echo
echo "== 4. 触发流水线 =="
curl -s -H "PRIVATE-TOKEN: $PAT" -o /tmp/pipe.json -w "  create pipeline http=%{http_code}\n" \
  -X POST "$GL/api/v4/projects/2/pipeline" -d "ref=main"
PIPE=$(jq -r '.id' /tmp/pipe.json); echo "  pipeline id=$PIPE web_url=$(jq -r '.web_url' /tmp/pipe.json)"
echo "$PIPE" > /root/podinfo-pipeline.id
sleep 10
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r '"  status=\(.status) ref=\(.ref) sha=\(.sha[0:7])"'
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name) status=\(.status)"'
