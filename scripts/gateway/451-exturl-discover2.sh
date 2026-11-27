#!/bin/bash
set -uo pipefail
BK=$(cat /tmp/exturl-backup-dir)

echo "########## Harbor env（core） ##########"
kubectl -n harbor get deploy harbor-core -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -Ei 'EXT_|CORE_URL|PORTAL|ENDPOINT|PUBLIC|TOKEN' || echo "  (无)"
echo "--- harbor-core configmap 里的关键项 ---"
kubectl -n harbor get cm | head -5
kubectl -n harbor get deploy harbor-core -o yaml > $BK/harbor-core-deploy.yaml && echo "  已备份 harbor-core deploy"

echo "########## Sonar serverBaseURL ##########"
SP=$(kubectl -n sonar get pod -o name | grep sonarqube | head -1)
kubectl -n sonar exec $SP -- sh -c 'curl -s -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL"' 2>&1 | head -c 300; echo

echo "########## Jenkins JCasC location ##########"
kubectl -n jenkins get cm | grep -i casc
JC=$(kubectl -n jenkins get cm -o name | grep -i casc | head -1)
kubectl -n $JC -o yaml 2>/dev/null | head -1
kubectl -n jenkins get $JC -o yaml > $BK/jenkins-casc.yaml 2>/dev/null && grep -nE "location|url:" $BK/jenkins-casc.yaml | head -10

echo "########## Keycloak 5 个 client 的回调现状 ##########"
KP=$(kubectl -n keycloak get pod -o name | grep -v db | head -1)
echo "  pod=$KP"
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" && echo "  登录 OK"
for c in gitlab harbor sonarqube argocd jenkins; do
  echo "--- $c"
  $KC get clients -r corp -q clientId=$c --fields clientId,redirectUris,webOrigins,rootUrl,baseUrl 2>&1 | tr -d "\n" | sed "s/  */ /g" | head -c 450; echo
done
echo "--- 全部 clientId 列表 ---"
$KC get clients -r corp --fields clientId 2>&1 | grep clientId
' 2>&1 | head -60
