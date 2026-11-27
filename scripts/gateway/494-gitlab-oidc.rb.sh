#!/bin/bash
set -uo pipefail
echo "=== GitLab 上注册的 omniauth provider ==="
gitlab-rails runner 'puts Gitlab::Auth::OAuth::Provider.providers.inspect' 2>&1 | tail -2
echo "=== 登录页是否渲染 SSO 按钮 ==="
curl -s -k https://gitlab.corp.local/users/sign_in -m 15 | grep -io 'keycloak[^<"]*' | head -2
curl -s -k https://gitlab.corp.local/users/sign_in -m 15 | grep -c 'omniauth' 
echo "=== 用 PAT 克隆（验证 runner 侧 DNS + 系统 CA） ==="
cd /tmp && rm -rf clone-test && timeout 60 git clone -q "https://oauth2:__GITLAB_PAT__@gitlab.corp.local/root/podinfo.git" clone-test 2>&1 | tail -3
ls /tmp/clone-test 2>/dev/null | head -3; rm -rf /tmp/clone-test
