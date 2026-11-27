#!/bin/bash
set -uo pipefail
echo "=== Grafana 管理员（Secret） ==="
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

echo "=== Jenkins 本地账号（JCasC） ==="
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml}' 2>/dev/null | grep -nE 'id:|password|realm|users' | head -20
echo "=== Jenkins 本地用户（配置文件，若有） ==="
kubectl -n jenkins exec deploy/jenkins -- sh -c 'ls /var/jenkins_home/users 2>/dev/null' 2>/dev/null | head -10

echo "=== Keycloak admin 用户 ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -Ei 'admin|hostname'

echo "=== 网关 Basic Auth 账号 ==="
kubectl -n gateway exec deploy/gateway -- cat /etc/nginx/auth/htpasswd 2>/dev/null | cut -d: -f1

echo "=== Harbor admin 用户（API 侧确认） ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' http://192.168.200.12:30090/api/v2.0/users/current | head -c 120; echo

echo "=== Sonar 本地账号列表（需 token） ==="
curl -s -u '__SONAR_CI_TOKEN__:' 'http://192.168.200.12:30091/api/users/search' | head -c 300; echo

