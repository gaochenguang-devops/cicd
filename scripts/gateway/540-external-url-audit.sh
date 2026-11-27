#!/bin/bash
set -uo pipefail
echo "=== GitLab external_url ==="
kubectl -n gitlab exec deploy/gitlab -- grep -E "^external_url" /etc/gitlab/gitlab.rb 2>/dev/null | head -2
echo "=== Keycloak KC_HOSTNAME ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'KC_HOSTNAME|KC_HTTP' 
echo "=== Harbor EXT_ENDPOINT ==="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
echo "=== ArgoCD server URL / insecure ==="
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.url}'; echo
kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].args}'; echo
echo "=== Jenkins 系统 URL（JCasC 里的） ==="
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml}' 2>/dev/null | grep -iE 'url:|rootUrl' | head -5
echo "=== Sonar Web 上下文 ==="
kubectl -n sonar get deploy sonarqube -o jsonpath='{.spec.template.spec.containers[0].env}' | tr ',' '\n' | grep -iE 'SONAR|CONTEXT|URL' | head -8
echo "=== Artifactory 外部 URL ==="
curl -sk -u 'admin:__ARTIFACTORY_ADMIN_PASS__' 'https://artifactory.corp.local/artifactory/api/system/configuration' 2>/dev/null | grep -oE '<urlBase>[^<]*' | head -2

