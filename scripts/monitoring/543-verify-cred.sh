#!/bin/bash
set -uo pipefail
echo "=== Keycloak admin（master realm password grant） ==="
curl -s -o /dev/null -w '  token -> %{http_code}\n' -X POST \
  'https://keycloak.corp.local/realms/master/protocol/openid-connect/token' \
  --resolve keycloak.corp.local:443:192.168.200.210 -k \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__'

echo "=== ArgoCD admin（sessions API） ==="
curl -s -o /dev/null -w '  session -> %{http_code}\n' -X POST \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"__ARGOCD_ADMIN_PASS__"}' \
  https://argocd.corp.local/api/v1/sessions --resolve argocd.corp.local:443:192.168.200.210 -k

echo "=== Sonar sonaradmin ==="
curl -s -o /dev/null -w '  api/authentication/validate -> %{http_code}\n' -u 'sonaradmin:__SONAR_ADMIN_PASS__' \
  'http://192.168.200.12:30091/api/authentication/validate'

echo "=== Artifactory admin ==="
curl -s -o /dev/null -w '  api/system/ping -> %{http_code}\n' -u 'admin:__ARTIFACTORY_ADMIN_PASS__' \
  'http://192.168.200.12:30092/artifactory/api/system/ping'

echo "=== Harbor admin ==="
curl -s -o /dev/null -w '  users/current -> %{http_code}\n' -u 'admin:__HARBOR_ADMIN_PASS__' \
  'http://192.168.200.12:30090/api/v2.0/users/current'

echo "=== GitLab root 基本认证 ==="
curl -s -o /dev/null -w '  /api/v4/user (private-token glpat) -> %{http_code}\n' \
  -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/user'

echo "=== 监控网关 Basic Auth ==="
curl -s -o /dev/null -w '  prometheus /targets -> %{http_code}\n' -u 'monitoring:__GATEWAY_BASIC_PASS__' \
  https://prometheus.corp.local/api/v1/targets --resolve prometheus.corp.local:443:192.168.200.210 -k

echo "=== Jenkins breakglass（本地账号） ==="
curl -s -o /dev/null -w '  /whoAmI/checkcrumb -> %{http_code}\n' -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' \
  'http://192.168.200.12:30088/whoAmI/api/json'

