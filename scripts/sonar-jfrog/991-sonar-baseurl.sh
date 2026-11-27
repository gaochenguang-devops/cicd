#!/usr/bin/env bash
set -uo pipefail
S=http://127.0.0.1:30091
curl -s -o /dev/null -w 'baseurl=%{http_code}\n' -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" -X POST $S/api/settings/set \
  --data-urlencode 'key=sonar.core.serverBaseURL' --data-urlencode 'value=http://192.168.200.12:30091'
curl -s -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" "$S/api/settings/values?keys=sonar.core.serverBaseURL" | head -c 200; echo

KC=http://192.168.200.12:30087
TOKEN=$(curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/corp/clients?clientId=sonarqube" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
curl -s -o /dev/null -w "redirect=%{http_code}\n" -X PUT "$KC/admin/realms/corp/clients/$ID" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"redirectUris":["http://192.168.200.12:30091/oauth2/callback/oidc"]}'
curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/corp/clients/$ID" | python3 -c 'import sys,json;print(json.load(sys.stdin)["redirectUris"])'
