#!/bin/bash
set -uo pipefail
KC=https://keycloak.corp.local/realms/corp

echo "########## 1. Jenkins：JCasC 里的 Keycloak 地址与 location ##########"
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml}' > /tmp/jenkins.yaml.before
cp /tmp/jenkins.yaml.before $(cat /tmp/exturl-backup-dir)/jenkins-casc.yaml.bak
sed -i 's#http://192.168.200.12:30087/realms/corp#https://keycloak.corp.local/realms/corp#g; s#http://192.168.200.12:30088/#https://jenkins.corp.local/#g' /tmp/jenkins.yaml.before
grep -nE "wellKnownOpenIDConfigurationUrl|location|url: " /tmp/jenkins.yaml.before | head -5
kubectl -n jenkins create cm jenkins-casc --from-file=jenkins.yaml=/tmp/jenkins.yaml.before --dry-run=client -o yaml | kubectl apply -f - | tail -1
kubectl -n jenkins rollout restart deploy/jenkins | tail -1

echo "########## 2. ArgoCD：url + dex 连接器 ##########"
python3 - <<'PY'
dex = """connectors:
- type: oidc
  id: keycloak
  name: Keycloak
  config:
    issuer: https://keycloak.corp.local/realms/corp
    clientID: argocd-dex
    clientSecret: __ARGOCD_DEX_OIDC_SECRET__
    insecureSkipVerify: true
    insecureSkipEmailVerified: true
    insecureEnableGroups: true
    getUserInfo: true
    scopes:
    - openid
    - profile
    - email
    - groups
oauth2:
  skipApprovalScreen: true
"""
import json
print(json.dumps({"data":{"url":"https://argocd.corp.local","dex.config":dex}}))
PY
python3 - <<'PY' > /tmp/argocd-patch.json
dex = """connectors:
- type: oidc
  id: keycloak
  name: Keycloak
  config:
    issuer: https://keycloak.corp.local/realms/corp
    clientID: argocd-dex
    clientSecret: __ARGOCD_DEX_OIDC_SECRET__
    insecureSkipVerify: true
    insecureSkipEmailVerified: true
    insecureEnableGroups: true
    getUserInfo: true
    scopes:
    - openid
    - profile
    - email
    - groups
oauth2:
  skipApprovalScreen: true
"""
import json
print(json.dumps({"data":{"url":"https://argocd.corp.local","dex.config":dex}}))
PY
kubectl -n argocd patch cm argocd-cm --type=merge -p "$(cat /tmp/argocd-patch.json)" | tail -1
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.url}{"\n"}'
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server | tail -2

echo "########## 3. Harbor：OIDC endpoint + EXT_ENDPOINT ##########"
HC=$(kubectl -n harbor get pod -o name | grep harbor-core | grep -v Terminating | head -1)
kubectl -n harbor exec $HC -c core -- sh -c "curl -s -X PUT -u admin:__HARBOR_ADMIN_PASS__ -H 'Content-Type: application/json' -d '{\"oidc_endpoint\":\"$KC\"}' http://localhost:8080/api/v2.0/configurations -w '\n  PUT HTTP=%{http_code}\n'"
kubectl -n harbor exec $HC -c core -- sh -c 'curl -s -u admin:__HARBOR_ADMIN_PASS__ http://localhost:8080/api/v2.0/configurations' | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  oidc_endpoint =", d["oidc_endpoint"]["value"])
'
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
kubectl -n harbor get cm harbor-core -o yaml > /tmp/harbor-cm-now.yaml
python3 - <<'PY'
import re
p="/tmp/harbor-cm-now.yaml"
s=open(p).read()
s=s.replace("EXT_ENDPOINT: http://192.168.200.12:30090","EXT_ENDPOINT: https://harbor.corp.local")
open(p,"w").write(s)
PY
grep -n "EXT_ENDPOINT" /tmp/harbor-cm-now.yaml
kubectl apply -f /tmp/harbor-cm-now.yaml | tail -1
kubectl -n harbor rollout restart deploy/harbor-core | tail -1

echo "########## 4. Sonar：serverBaseURL + issuerUri ##########"
ST=__SONAR_CI_TOKEN__
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c "
curl -s -o /dev/null -w '  serverBaseURL %{http_code}\n' -X POST -u $ST: -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'key=sonar.core.serverBaseURL' --data-urlencode 'value=https://sonar.corp.local' http://localhost:9000/api/settings/set
curl -s -o /dev/null -w '  issuerUri    %{http_code}\n' -X POST -u $ST: -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'key=sonar.auth.oidc.issuerUri' --data-urlencode 'value=$KC' http://localhost:9000/api/settings/set
"
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c "curl -s -u $ST: 'http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL,sonar.auth.oidc.issuerUri'"
echo
