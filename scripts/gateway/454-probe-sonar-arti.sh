#!/bin/bash
set -uo pipefail
echo "=== Sonar：带状态码探测 ==="
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c '
curl -sS -w "\nHTTP=%{http_code}\n" -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL" 
curl -sS -w "\nHTTP=%{http_code}\n" -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/system/status"
' 2>&1 | head -20
echo "=== Sonar 容器内可用工具 ==="
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'command -v curl wget; ls /opt/sonarqube/conf' 2>&1 | head -10
echo "=== Artifactory urlBase 相关 ==="
kubectl -n artifactory exec deploy/artifactory -- sh -c 'curl -s -u admin:__ARTIFACTORY_ADMIN_PASS__ "http://localhost:8082/artifactory/api/system/version"; echo; curl -s -u admin:__ARTIFACTORY_ADMIN_PASS__ "http://localhost:8082/artifactory/api/oauth2/settings" | head -c 400' 2>&1 | head -10
