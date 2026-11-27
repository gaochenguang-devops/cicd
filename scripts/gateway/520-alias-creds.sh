#!/bin/bash
set -uo pipefail
U='robot$apps+ci-builder'
P='__HARBOR_ROBOT_CI_SECRET__'
echo "=== 带凭据、用 IP 名拉私有镜像（含 containerd 别名） ==="
crictl pull --creds "$U:$P" 192.168.200.12:30090/apps/redis:7-alpine 2>&1 | tail -3
echo
echo "=== 看 registry 侧返回的 realm（浏览器/客户端实际被指向哪） ==="
curl -s -i http://192.168.200.12:30090/v2/ -m 8 | grep -i 'www-authenticate'
curl -s -i -k https://harbor.corp.local/v2/ -m 8 | grep -i 'www-authenticate'
echo
echo "=== 因为 realm 是域名，试探 containerd 能否拿到 token（curl 域名 token 端点，带 robot 凭据） ==="
curl -s -o /dev/null -w '  https://harbor.corp.local/service/token -> %{http_code}\n' -k -u "$U:$P" \
  "https://harbor.corp.local/service/token?service=harbor-registry&scope=repository:apps/redis:pull" -m 10
