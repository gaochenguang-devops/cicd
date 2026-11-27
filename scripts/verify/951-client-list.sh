#!/usr/bin/env bash
set -u
T=$(curl -s -d "client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__&grant_type=password" http://127.0.0.1:30087/realms/master/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
for c in gitlab jenkins harbor argocd argocd-dex; do
  echo "== $c"
  curl -s -H "Authorization: Bearer $T" "http://127.0.0.1:30087/admin/realms/corp/clients?clientId=$c" \
   | python3 -c 'import sys,json;d=json.load(sys.stdin);print("missing" if not d else {"id":d[0]["clientId"],"redirect":d[0].get("redirectUris"),"pkce":(d[0].get("attributes") or {}).get("pkce.code.challenge.method"),"direct":d[0].get("directAccessGrantsEnabled")})'
done
