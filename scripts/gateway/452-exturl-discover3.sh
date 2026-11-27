#!/bin/bash
set -uo pipefail
BK=$(cat /tmp/exturl-backup-dir)

echo "########## gitlab.rb 中的 omniauth / 相关行 ##########"
grep -nE "omniauth|issuer|redirect_uri|client_options|identifier|external_url|trusted_proxies" /etc/gitlab/gitlab.rb | head -30

echo "########## harbor-core configmap 关键键 ##########"
kubectl -n harbor get cm harbor-core -o jsonpath='{.data}' | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k,v in d.items():
    if any(s in k.upper() for s in ("ENDPOINT","URL","OIDC","PORTAL","TOKEN")):
        print(" ",k,"=",str(v)[:160])
'
kubectl -n harbor get cm harbor-core -o yaml > $BK/harbor-core-cm.yaml && echo "  已备份 harbor-core cm"
echo "--- harbor 当前 auth_mode / oidc 配置（API） ---"
kubectl -n harbor get svc harbor-core -o jsonpath='{.spec.clusterIP}{":80\n"}'

echo "########## Sonar OIDC / baseURL 设置 ##########"
kubectl -n sonar exec -c sonarqube sonarqube-56448d7c5d-c8lml -- sh -c 'curl -s -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL,sonar.auth.oidc.issuerUri,sonar.auth.oidc.clientId.secured,sonar.auth.oidc.enabled"' 2>&1 | head -c 600; echo

echo "########## argocd-cm 全量 data ##########"
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data}' | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k,v in d.items():
    print("---",k)
    print(v[:800])
'
echo "########## artifactory 的 OIDC 客户端回调 ##########"
kubectl -n keycloak exec $(kubectl -n keycloak get pod -o name | grep -v db | head -1) -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1
$KC get clients -r corp -q clientId=artifactory --fields clientId,redirectUris,webOrigins 2>&1 | tr -d "\n" | head -c 400; echo
' 2>&1 | tail -3
