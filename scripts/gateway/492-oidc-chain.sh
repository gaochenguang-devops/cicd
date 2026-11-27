#!/bin/bash
set -uo pipefail
show() { printf "== %s\n" "$1"; curl -s -o /dev/null -D - -k "$1" -m 15 | grep -iE '^HTTP|^location' | head -3 | sed 's/^/   /'; }

show "https://gitlab.corp.local/users/auth/openid_connect"
show "https://harbor.corp.local/c/oidc/login"
show "https://sonar.corp.local/sessions/init/oidc"
show "https://jenkins.corp.local/securityRealm/commenceLogin"
echo "== ArgoCD：先拿 /auth/login 的 Location，再跟一跳"
L=$(curl -s -o /dev/null -D - -k https://argocd.corp.local/auth/login -m 15 | grep -i '^location' | tr -d '\r' | sed 's/Location: //I')
echo "   auth/login -> $L"
if [ -n "$L" ]; then
  case "$L" in /*) L2="https://argocd.corp.local$L";; *) L2="$L";; esac
  curl -s -o /dev/null -D - -k "$L2" -m 15 | grep -iE '^HTTP|^location' | head -3 | sed 's/^/   /'
fi
echo "== Jenkins 日志里 OIDC 相关错误 =="
kubectl -n jenkins logs deploy/jenkins 2>&1 | grep -iE "oidc|openid|discovery" | grep -iE "error|fail|exception" | tail -5 || echo "   无"
