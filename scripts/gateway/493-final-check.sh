#!/bin/bash
set -uo pipefail
echo "=== GitLab 登录页上的 SSO 按钮链接 ==="
curl -s -k https://gitlab.corp.local/users/sign_in -m 15 | grep -oE 'href="[^"]*openid[^"]*"' | head -3
echo "=== GitLab OmniAuth 起始（带 -L 观察） ==="
curl -s -o /dev/null -D - -k -H "X-Requested-With: XMLHttpRequest" https://gitlab.corp.local/users/auth/openid_connect -m 15 | grep -iE '^HTTP|^location' | head -3
echo "=== 宿主 git 走 https://gitlab.corp.local 克隆（验证 runner 侧 DNS+CA） ==="
cd /tmp && rm -rf clone-test && timeout 60 git clone -q "https://oauth2:__GITLAB_PAT__@gitlab.corp.local/root/podinfo.git" clone-test 2>&1 | tail -3 && ls clone-test | head -3 && cd / && rm -rf /tmp/clone-test
echo "=== Harbor OIDC 配置（重启后仍在） ==="
HC=$(kubectl -n harbor get pod -o name | grep harbor-core | grep -v Terminating | head -1)
kubectl -n harbor exec $HC -c core -- sh -c 'curl -s -u admin:__HARBOR_ADMIN_PASS__ http://localhost:8080/api/v2.0/configurations' | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in ("oidc_endpoint","auth_mode"):
    print("  ",k,"=",d[k]["value"])
'
echo "=== ArgoCD settings ==="
curl -s -k https://argocd.corp.local/api/v1/settings | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  url =", d.get("url"))
print("  oidcConfig =", str(d.get("oidcConfig"))[:180])
' 2>&1 | head -4
echo "=== Sonar serverBaseURL ==="
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'curl -s -H "Authorization: Bearer __SONAR_CI_TOKEN__" "http://localhost:9000/api/settings/values?keys=sonar.core.serverBaseURL"' 
echo
