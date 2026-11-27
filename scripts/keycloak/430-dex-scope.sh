#!/usr/bin/env bash
set -u
KC=http://127.0.0.1:30087
T=$(curl -s -d "client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__&grant_type=password" $KC/realms/master/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
CID=$(curl -s -H "Authorization: Bearer $T" "$KC/admin/realms/corp/clients?clientId=argocd-dex" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
echo "client id $CID"
curl -s -H "Authorization: Bearer $T" "$KC/admin/realms/corp/clients/$CID/default-client-scopes" | python3 -c 'import sys,json;print([x["name"] for x in json.load(sys.stdin)])'
echo "--- adding groups scope if missing"
curl -s -X PUT -H "Authorization: Bearer $T" "$KC/admin/realms/corp/clients/$CID/default-client-scopes/$(curl -s -H "Authorization: Bearer $T" "$KC/admin/realms/corp/client-scopes" | python3 -c 'import sys,json;print([x["id"] for x in json.load(sys.stdin) if x["name"]=="groups"][0])')" -o /dev/null -w "put:%{http_code}\n"
curl -s -H "Authorization: Bearer $T" "$KC/admin/realms/corp/clients/$CID/default-client-scopes" | python3 -c 'import sys,json;print([x["name"] for x in json.load(sys.stdin)])'
