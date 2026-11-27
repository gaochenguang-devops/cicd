#!/usr/bin/env bash
set -eu
T=$(curl -s -d "client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__&grant_type=password" http://127.0.0.1:30087/realms/master/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
python3 - "$T" <<'PY'
import sys,json,urllib.request
t=sys.argv[1]; base="http://127.0.0.1:30087/admin/realms/corp/clients"
def get(cid):
    return json.load(urllib.request.urlopen(urllib.request.Request(f"{base}?clientId={cid}",headers={"Authorization":"Bearer "+t})))[0]
for cid in ["gitlab","harbor"]:
    c=get(cid); c["directAccessGrantsEnabled"]=False
    urllib.request.urlopen(urllib.request.Request(f"{base}/{c['id']}",data=json.dumps(c).encode(),
        headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="PUT"))
    print(cid,"direct grants -> off")
# dedicated CLI test client
body={"clientId":"cli-test","name":"CLI 手工验证","enabled":True,"protocol":"openid-connect",
 "publicClient":False,"clientAuthenticatorType":"client-secret","secret":"__CLI_TEST_OIDC_SECRET__",
 "standardFlowEnabled":False,"implicitFlowEnabled":False,"directAccessGrantsEnabled":True,
 "serviceAccountsEnabled":False,"redirectUris":[],
 "attributes":{"pkce.code.challenge.method":""}}
try:
    urllib.request.urlopen(urllib.request.Request(base,data=json.dumps(body).encode(),
        headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="POST"))
    print("cli-test created")
except Exception as e:
    print("cli-test exists?",getattr(e,"code",e))
PY
