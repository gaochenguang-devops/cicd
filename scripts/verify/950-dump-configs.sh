#!/usr/bin/env bash
set -u
echo "===== argocd-cm dex.config ====="
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}'
echo "===== argocd-cm url ====="
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.url}'
echo "===== jenkins-casc ====="
kubectl -n jenkins get cm jenkins-casc -o yaml | sed -n '1,80p'
echo "===== gitlab.rb oidc block ====="
grep -n -A40 "omniauth_providers" /etc/gitlab/gitlab.rb | head -60
echo "===== harbor oidc settings ====="
HARBOR_PW='__HARBOR_ADMIN_PASS__'
curl -s -u "admin:$HARBOR_PW" 'http://127.0.0.1:30090/api/v2.0/configurations' | python3 -c 'import sys,json;d=json.load(sys.stdin);print({k:v for k,v in d.items() if k.startswith("oidc") or k=="auth_mode"})'
