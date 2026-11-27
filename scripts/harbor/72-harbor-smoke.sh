#!/usr/bin/env bash
set -uo pipefail
H=http://192.168.200.12:30090
ADMIN="admin:__HARBOR_ADMIN_PASS__"
echo "== 项目 apps =="
curl -s -u "$ADMIN" -H 'Content-Type: application/json' -o /tmp/p.json -w "  create http=%{http_code}\n" \
  -X POST "$H/api/v2.0/projects" -d '{"project_name":"apps","public":false,"metadata":{"public":"false"}}'
head -c 200 /tmp/p.json; echo
curl -s -u "$ADMIN" "$H/api/v2.0/projects" | jq -r '.[] | "  项目: \(.name) public=\(.metadata.public)"'
echo
echo "== 机器人账号（CI push）=="
curl -s -u "$ADMIN" -H 'Content-Type: application/json' -o /tmp/r.json -w "  robot http=%{http_code}\n" \
  -X POST "$H/api/v2.0/robots" -d '{"name":"ci-builder","level":"project","project_name":"apps","duration":90,"permissions":[{"kind":"project","namespace":"apps","access":[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"}]}]}'
cat /tmp/r.json | jq -r '"  name=\(.name) secret=\(.secret[0:8])...(len \(.secret|length))"'
ROBOT_NAME=$(jq -r '.name' /tmp/r.json); ROBOT_SECRET=$(jq -r '.secret' /tmp/r.json)
printf '%s\n%s\n' "$ROBOT_NAME" "$ROBOT_SECRET" > /root/harbor-ci-creds.txt
chmod 600 /root/harbor-ci-creds.txt
echo "  凭据已存 /root/harbor-ci-creds.txt"
echo
echo "== podman login =="
podman login --tls-verify=false -u "$ROBOT_NAME" -p "$ROBOT_SECRET" 192.168.200.12:30090 2>&1 | tail -2
echo
echo "== push 验证 =="
podman pull -q docker.m.daocloud.io/library/busybox:1.36 >/dev/null 2>&1
podman tag docker.m.daocloud.io/library/busybox:1.36 192.168.200.12:30090/apps/busybox:v1
podman push --tls-verify=false 192.168.200.12:30090/apps/busybox:v1 2>&1 | tail -3
echo
echo "== 仓库中的制品 =="
curl -s -u "$ADMIN" "$H/api/v2.0/projects/apps/repositories" | jq -r '.[] | "  \(.name) artifacts=\(.artifact_count)"'
echo
echo "== 删除本地镜像后从 Harbor 拉回 =="
podman rmi 192.168.200.12:30090/apps/busybox:v1 >/dev/null 2>&1
podman pull -q --tls-verify=false 192.168.200.12:30090/apps/busybox:v1 2>&1 | tail -2
podman images | grep 30090 | head -2
