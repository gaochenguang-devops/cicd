#!/usr/bin/env bash
set -euo pipefail
KC=http://192.168.200.12:30087
REALM=corp

TOKEN=$(curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
if [ -z "$TOKEN" ]; then echo "KEYCLOAK_TOKEN_FAIL"; exit 1; fi

mk () {
  local cid="$1" secret="$2" redirects="$3"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$KC/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"clientId\":\"$cid\",\"name\":\"$cid\",\"enabled\":true,\"protocol\":\"openid-connect\",\"publicClient\":false,\"secret\":\"$secret\",\"standardFlowEnabled\":true,\"implicitFlowEnabled\":false,\"directAccessGrantsEnabled\":false,\"serviceAccountsEnabled\":false,\"redirectUris\":$redirects,\"webOrigins\":[\"+\"],\"attributes\":{\"pkce.code.challenge.method\":\"\",\"post.logout.redirect.uris\":\"+\"}}")
  echo "create $cid -> $code"
}

mk sonarqube '__SONAR_OIDC_SECRET__' '["http://192.168.200.12:30091/oauth2/callback/sonarqube"]'
mk artifactory 'ArtiOIDC@2026Secret' '["http://192.168.200.12:30092/ui/api/v1/oauth2/callback","http://192.168.200.12:30092/artifactory/api/oauth2/callback"]'

echo "== 结果 =="
for c in sonarqube artifactory; do
  curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$REALM/clients?clientId=$c" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); c=d[0] if d else {}; print(c.get('clientId'), c.get('redirectUris'), c.get('attributes',{}).get('pkce.code.challenge.method'), c.get('publicClient'))"
done
