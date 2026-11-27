#!/bin/bash
set -uo pipefail
check() {
  local name="$1"; local url="$2"
  local body
  body=$(curl -s -k -L -c /tmp/ck.txt "$url" -m 20)
  if echo "$body" | grep -qi "Invalid parameter"; then
    echo "  $name: ❌ 仍报 Invalid parameter: redirect_uri"
  elif echo "$body" | grep -qiE "kc-form-login|login|用户名|Username"; then
    echo "  $name: ✅ 已进入 Keycloak 登录页"
  else
    echo "  $name: ? 返回 $(echo "$body" | wc -c) 字节，片段: $(echo "$body" | head -c 120 | tr -d '\n')"
  fi
}
echo "=== Harbor ==="
URL=$(curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login -m 15 | grep -i '^location' | tr -d '\r' | sed 's/Location: //I')
check harbor "$URL"
echo "=== ArgoCD ==="
RAW=$(curl -s -o /dev/null -D - -k "https://argocd.corp.local/api/dex/auth/keycloak?client_id=argo-cd&redirect_uri=https%3A%2F%2Fargocd.corp.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=x" -m 15 | grep -i '^location' | tr -d '\r' | sed 's/Location: //I')
check argocd "$RAW"
