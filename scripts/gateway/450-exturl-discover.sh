#!/bin/bash
set -uo pipefail
echo "########## 0. 备份目录 ##########"
TS=$(date +%Y%m%d-%H%M%S)
BK=/root/exturl-backup-$TS
mkdir -p $BK
echo "  $BK"
echo "$BK" >/tmp/exturl-backup-dir

echo "########## 1. GitLab external_url 现状 ##########"
grep -nE "^external_url|^nginx\['|trusted_proxies|letsencrypt" /etc/gitlab/gitlab.rb || echo "  (无显式配置)"
cp /etc/gitlab/gitlab.rb $BK/gitlab.rb.bak && echo "  已备份 gitlab.rb"

echo "########## 2. Keycloak 部署 env 现状 ##########"
KCNS=$(kubectl get deploy -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' | grep -i keycloak | head -1)
echo "  keycloak = $KCNS"
NS=$(echo $KCNS | awk '{print $1}'); DN=$(echo $KCNS | awk '{print $2}')
kubectl -n $NS get deploy $DN -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'KC_|KEYCLOAK' || echo "  (无 KC_ 环境变量)"
kubectl -n $NS get deploy $DN -o yaml > $BK/keycloak-deploy.yaml && echo "  已备份 keycloak deployment"

echo "########## 3. ArgoCD cm url ##########"
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.url}{"\n"}' 2>&1
kubectl -n argocd get cm argocd-cm -o yaml > $BK/argocd-cm.yaml 2>/dev/null && echo "  已备份 argocd-cm"

echo "########## 4. Harbor 相关 env（EXT_ENDPOINT / CORE_URL / PORTAL_URL） ##########"
for ns in harbor harbor-system; do
  kubectl -n $ns get deploy -o name 2>/dev/null | head -5
done
kubectl get deploy -A -o wide 2>/dev/null | grep -i harbor | head -5

echo "########## 5. Sonar serverBaseURL ##########"
kubectl get pods -A 2>/dev/null | grep -i sonar | head -3

echo "########## 6. Jenkins JCasC location ##########"
kubectl get pods -A 2>/dev/null | grep -i jenkins | head -3

echo "########## 7. Keycloak 里 corp realm 的 5 个 client 回调现状 ##########"
KC_POD=$(kubectl -n $NS get pod -l app=keycloak -o name 2>/dev/null | head -1)
[ -z "$KC_POD" ] && KC_POD=$(kubectl -n $NS get pod -o name | grep -i keycloak | grep -v db | head -1)
echo "  pod=$KC_POD"
if [ -n "$KC_POD" ]; then
kubectl -n $NS exec $KC_POD -- /bin/sh -c '
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "Admin@2026Keycloak" >/dev/null 2>&1
for c in gitlab harbor sonarqube argocd jenkins; do
  echo "--- $c"
  /opt/keycloak/bin/kcadm.sh get clients -r corp -q clientId=$c --fields clientId,redirectUris,webOrigins,attributes 2>/dev/null | tr -d " \n" | head -c 400; echo
done' 2>&1 | head -40
fi
