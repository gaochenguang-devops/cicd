#!/usr/bin/env bash
set -uo pipefail
KC=http://192.168.200.12:30087
TOKEN=$(curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/corp/clients?clientId=sonarqube" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
curl -s -o /dev/null -w "redirect update -> %{http_code}\n" -X PUT \
  "$KC/admin/realms/corp/clients/$ID" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"redirectUris":["http://192.168.200.12:30091/oauth2/callback/authoidc"]}'
curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/corp/clients/$ID" \
  | python3 -c 'import sys,json;print("redirectUris:", json.load(sys.stdin)["redirectUris"])'

S=http://127.0.0.1:30091
setp () { curl -s -o /dev/null -w "$1 -> %{http_code}\n" -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" -X POST "$S/api/settings/set" --data-urlencode "key=$1" --data-urlencode "value=$2"; }
setp sonar.auth.oidc.enabled true
setp sonar.auth.oidc.issuerUri http://192.168.200.12:30087/realms/corp
setp sonar.auth.oidc.clientId.secured sonarqube
setp sonar.auth.oidc.clientSecret.secured '__SONAR_OIDC_SECRET__'
setp sonar.auth.oidc.scopes 'openid profile email'
setp sonar.auth.oidc.loginButtonText 'Keycloak'
setp sonar.auth.oidc.allowUsersToSignUp true
setp sonar.auth.oidc.groupsSync true
setp sonar.auth.oidc.groupsSync.claimName groups
setp sonar.auth.oidc.loginStrategy 'Preferred username'

echo "== 回读 =="
curl -s -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" "$S/api/settings/values?keys=sonar.auth.oidc.enabled,sonar.auth.oidc.issuerUri,sonar.auth.oidc.clientId.secured,sonar.auth.oidc.scopes,sonar.auth.oidc.groupsSync" | head -c 800; echo
echo "== 登录页是否出现按钮 =="
curl -s "$S/api/settings/values?keys=sonar.auth.oidc.enabled" >/dev/null
curl -s -o /dev/null -w 'login-page=%{http_code}\n' "$S/sessions/new"
