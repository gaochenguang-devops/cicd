#!/usr/bin/env bash
set -eu
KC=http://127.0.0.1:30087
T=$(curl -s -d "client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__&grant_type=password" $KC/realms/master/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
python3 - "$T" <<'PY'
import sys,json,urllib.request
t=sys.argv[1]
body={"clientId":"argocd-dex","name":"argocd-dex","enabled":True,"protocol":"openid-connect",
 "publicClient":False,"clientAuthenticatorType":"client-secret","secret":"__ARGOCD_DEX_OIDC_SECRET__",
 "standardFlowEnabled":True,"implicitFlowEnabled":False,"directAccessGrantsEnabled":False,
 "serviceAccountsEnabled":False,"redirectUris":["http://192.168.200.12:30080/api/dex/callback"],
 "attributes":{"pkce.code.challenge.method":"","post.logout.redirect.uris":"http://192.168.200.12:30080/*"}}
try:
    r=urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:30087/admin/realms/corp/clients",
        data=json.dumps(body).encode(),headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="POST"))
    print("created", r.status)
except Exception as e:
    print("create err", e.code if hasattr(e,"code") else e, getattr(e,"read",lambda:b"")()[:200])
PY
