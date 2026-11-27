#!/bin/bash
set -uo pipefail
echo "########## Sonar（正确指定容器） ##########"
kubectl -n sonar get pod -o name | grep sonarqube
SP=$(kubectl -n sonar get pod -o name | grep sonarqube | head -1)
kubectl -n sonar exec $SP -c sonarqube -- sh -c 'curl -s -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL,sonar.auth.oidc.issuerUri,sonar.auth.oidc.clientId.secured,sonar.auth.oidc.enabled,sonar.auth.oidc.loginButtonText"' 2>&1 | head -c 800; echo
echo "--- 所有 oidc/serverBase 设置 ---"
kubectl -n sonar exec $SP -c sonarqube -- sh -c 'curl -s -u admin:__SONAR_ADMIN_PASS__ "http://localhost:9000/api/settings/values" ' 2>&1 | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception as e: print(raw[:300]); raise SystemExit
for s in d.get("settings",[]):
    k=s.get("key","")
    if "oidc" in k or "serverBase" in k or "sso" in k or "sam" in k:
        print(" ",k,"=",str(s.get("value",s.get("values")))[:120])
' 2>&1 | head -20

echo "########## Harbor OIDC 配置（API） ##########"
HC=$(kubectl -n harbor get pod -o name | grep harbor-core | head -1)
kubectl -n harbor exec $HC -c core -- sh -c 'curl -s -u admin:__HARBOR_ADMIN_PASS__ "http://localhost:8080/api/v2.0/configurations" -H "accept: application/json"' 2>&1 | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except: print(raw[:200]); raise SystemExit
for k in ("auth_mode","oidc_name","oidc_endpoint","oidc_client_id","oidc_scope","oidc_groups_claim","oidc_admin_group","oidc_user_claim","oidc_auto_onboard","oidc_extra_redirect_parms","external_url","self_registration"):
    if k in d: print(" ",k,"=",str(d[k])[:160])
' 2>&1 | head -20

echo "########## Artifactory OIDC 配置（API） ##########"
AR=$(kubectl get pod -A -o wide | grep -i artifactory | head -2)
echo "$AR"
APOD=$(kubectl -n artifactory get pod -o name 2>/dev/null | grep -i artifactory | head -1)
[ -z "${APOD:-}" ] && APOD=$(kubectl get pod -A -o name | grep -i artifactory | head -1)
echo "  pod=$APOD"
if [ -n "$APOD" ]; then
kubectl exec $APOD -- sh -c 'curl -s -u admin:__ARTIFACTORY_ADMIN_PASS__ "http://localhost:8082/artifactory/api/oauth2/settings" -H "accept: application/json"' 2>&1 | head -c 500; echo
fi
