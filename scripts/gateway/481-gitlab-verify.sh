#!/bin/bash
set -uo pipefail
echo "=== GitLab：站点与跳转 ==="
curl -s -o /dev/null -D - https://gitlab.corp.local/ -m 15 | grep -iE '^HTTP|^location'
curl -s -o /dev/null -w "  /users/sign_in -> %{http_code}\n" https://gitlab.corp.local/users/sign_in -m 15
echo "=== OIDC 起始跳转（看 redirect_uri 是否正确） ==="
curl -s -o /dev/null -D - -H 'Connection: close' https://gitlab.corp.local/users/auth/openid_connect -m 15 | grep -iE '^HTTP|^location' | head -3
echo "=== GitLab 到 Keycloak 的回连（证书信任） ==="
curl -s -o /dev/null -w "  gitlab->kc %{http_code}\n" https://keycloak.corp.local/realms/corp/.well-known/openid-configuration -m 10
