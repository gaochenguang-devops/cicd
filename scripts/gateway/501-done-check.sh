#!/bin/bash
set -uo pipefail
echo "=== ArgoCD dex 第三跳：dex/keycloak -> ? ==="
L=$(curl -s -o /dev/null -D - -k "https://argocd.corp.local/api/dex/auth/keycloak?client_id=argo-cd&redirect_uri=https%3A%2F%2Fargocd.corp.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=x" -m 15 | grep -i '^location' | tr -d '\r' | sed 's/Location: //I')
echo "  -> ${L:0:160}"
echo "=== ArgoCD server 日志里的 OIDC 错误 ==="
kubectl -n argocd logs deploy/argocd-server --tail=60 2>&1 | grep -iE "oidc|dex|error" | tail -6 || echo "  无"
echo "=== Sonar 重启后 issuerUri === "
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'curl -s -H "Authorization: Bearer __SONAR_CI_TOKEN__" "http://localhost:9000/api/settings/values?keys=sonar.auth.oidc.issuerUri"'
echo
echo "=== 最后一次站点矩阵 ==="
for h in harbor sonar artifactory argocd gitlab keycloak jenkins prometheus alertmanager ldapadmin podinfo webapp; do
  printf "  %-13s %s\n" $h $(curl -s -o /dev/null -k -w "%{http_code}" https://$h.corp.local/ -m 12)
done
