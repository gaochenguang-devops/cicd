#!/bin/bash
set -uo pipefail
KP=$(kubectl -n keycloak get pod -o name | grep -v db | grep -v Terminating | head -1)
echo "keycloak pod = $KP"

echo "===== 1. 把 6 个 client 的回调/来源域名先切到 https://*.corp.local ====="
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1 || exit 1
upd() {
  CID=$1; URIS=$2
  ID=$($KC get clients -r corp -q clientId=$CID --fields id --format csv --noquotes 2>/dev/null | tail -1)
  [ -z "$ID" ] && { echo "  !! $CID 未找到"; return; }
  $KC update clients/$ID -r corp -s "redirectUris=[\"${URIS}\"]" -s "webOrigins=[\"+\"]" >/dev/null 2>&1 \
    && echo "  $CID -> $URIS" || echo "  !! $CID 更新失败"
}
upd gitlab      "https://gitlab.corp.local/users/auth/openid_connect/callback"
upd harbor      "https://harbor.corp.local/c/oidc/callback"
upd sonarqube   "https://sonar.corp.local/oauth2/callback/oidc"
upd argocd      "https://argocd.corp.local/auth/callback"
upd jenkins     "https://jenkins.corp.local/securityRealm/finishLogin"
upd artifactory "https://artifactory.corp.local/ui/api/v1/oauth2/callback"
echo "  --- 回读 ---"
for c in gitlab harbor sonarqube argocd jenkins; do
  echo -n "  $c: "; $KC get clients -r corp -q clientId=$c --fields redirectUris --format csv --noquotes | tail -1
done
'

echo "===== 2. Keycloak 自身 hostname 切到 https ====="
kubectl -n keycloak patch deploy keycloak --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"KC_HOSTNAME","value":"https://keycloak.corp.local"}}
]' 2>/dev/null || kubectl -n keycloak patch deploy keycloak --type=json -p='[
 {"op":"replace","path":"/spec/template/spec/containers/0/env/4","value":{"name":"KC_HOSTNAME","value":"https://keycloak.corp.local"}}
]'
kubectl -n keycloak rollout status deploy/keycloak --timeout=180s | tail -1
sleep 5
echo "===== 3. 验证 issuer 已变成 https://keycloak.corp.local ====="
NP=$(kubectl -n podinfo get pod -o name | head -1)
kubectl -n podinfo exec $NP -- sh -c 'curl -s https://keycloak.corp.local/realms/corp/.well-known/openid-configuration' | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in ("issuer","authorization_endpoint","token_endpoint","jwks_uri","end_session_endpoint"):
    print("  ",k,"=",d.get(k))
'
echo "===== 4. 从宿主（系统 CA 已信任）再验一次 ====="
curl -s https://keycloak.corp.local/realms/corp/.well-known/openid-configuration | python3 -c 'import json,sys;print("  issuer =",json.load(sys.stdin)["issuer"])'
