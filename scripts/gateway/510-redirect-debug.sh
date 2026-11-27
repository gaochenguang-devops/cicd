#!/bin/bash
set -uo pipefail
KP=$(kubectl -n keycloak get pod -o name | grep -v db | grep -v Terminating | head -1)
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1 || exit 1
for c in harbor argocd argocd-dex gitlab sonarqube jenkins artifactory; do
  echo "--- $c"
  $KC get clients -r corp -q clientId=$c --fields clientId,redirectUris,webOrigins,rootUrl,baseUrl,publicClient,attributes 2>&1 | tr -d "\n" | sed "s/  */ /g" | head -c 700; echo
done
'
echo "=== Harbor 实际发出的 redirect_uri ==="
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login -m 15 | grep -i '^location' | tr -d '\r' | head -2
echo "=== ArgoCD dex 实际发出的 redirect_uri ==="
curl -s -o /dev/null -D - -k "https://argocd.corp.local/api/dex/auth/keycloak?client_id=argo-cd&redirect_uri=https%3A%2F%2Fargocd.corp.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=x" -m 15 | grep -i '^location' | tr -d '\r' | sed 's/&state=.*//'
