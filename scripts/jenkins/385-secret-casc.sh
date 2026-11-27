#!/bin/bash
set -uo pipefail
echo "=== 1) 建 Secret jenkins-casc-secrets ==="
kubectl -n jenkins create secret generic jenkins-casc-secrets \
  --from-literal=GITLAB_PAT='__GITLAB_PAT__' \
  --from-literal=HARBOR_CI_PASS='__HARBOR_ROBOT_JENKINS_SECRET__' \
  --from-literal=HARBOR_LIB_PASS='__HARBOR_ROBOT_LIB_SECRET__' \
  --from-literal=SONAR_TOKEN='__SONAR_CI_TOKEN__' \
  --from-literal=ARTI_USER='admin' \
  --from-literal=ARTI_PASS='__ARTIFACTORY_ADMIN_PASS__' \
  --from-literal=OIDC_CLIENT_SECRET='__JENKINS_OIDC_SECRET__' \
  --from-literal=BREAKGLASS_PASS='__JENKINS_BREAKGLASS_PASS__' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n jenkins get secret jenkins-casc-secrets -o jsonpath='{.data}' | python3 -c 'import sys,json;print("keys:",sorted(json.load(sys.stdin).keys()))'

echo "=== 2) 给 Deployment 加 envFrom（Secret 全部键注入容器） ==="
kubectl -n jenkins set env deploy/jenkins --from=secret/jenkins-casc-secrets >/dev/null && echo "envFrom ok"
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo

echo "=== 3) 更新 ConfigMap（敏感值已改为 \${VAR}） ==="
kubectl -n jenkins create configmap jenkins-casc \
  --from-file=jenkins.yaml=/root/jenkins-casc/jenkins-casc-full.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
echo "ConfigMap 里还有没有明文口令（应只剩 \${...}）:"
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml}' | base64 -d | grep -nE 'password|secret|glpat|squ_|cyvRD|QFMiV|Artifactory@|\$\{'
