#!/usr/bin/env bash
set -eu
T=$(curl -s -d "client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__&grant_type=password" http://127.0.0.1:30087/realms/master/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
python3 - "$T" <<'PY'
import sys,json,urllib.request
t=sys.argv[1]; base="http://127.0.0.1:30087/admin/realms/corp/clients"
c=json.load(urllib.request.urlopen(urllib.request.Request(f"{base}?clientId=jenkins",headers={"Authorization":"Bearer "+t})))[0]
c["directAccessGrantsEnabled"]=False
urllib.request.urlopen(urllib.request.Request(f"{base}/{c['id']}",data=json.dumps(c).encode(),
  headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="PUT"))
print("jenkins direct grants -> off")
PY
echo "--- test cli-test token"
curl -s -d "client_id=cli-test&client_secret=__CLI_TEST_OIDC_SECRET__&grant_type=password&username=dev01&password=__LDAP_USER_INIT_PASS_URLENC__&scope=openid" \
 http://127.0.0.1:30087/realms/corp/protocol/openid-connect/token | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sorted(d)[:4])'
