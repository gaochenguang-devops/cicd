#!/usr/bin/env bash
set -uo pipefail
echo "== Jenkins JCasC keys =="
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data}' | head -c 300; echo
echo "== Jenkins 安全配置摘要 =="
kubectl -n jenkins get cm jenkins-casc -o json 2>/dev/null | python3 -c '
import sys,json,re
d=json.load(sys.stdin)["data"]
for k,v in d.items():
    if k.endswith((".yaml",".yml",".d")):
        for line in v.splitlines():
            if re.search(r"(securityRealm|authorizationStrategy|globalMatrix|oidc|ldap|clientId|issu|serverUrl|groups|admin)", line, re.I):
                print(" ", line.strip()[:160])'
echo
echo "== Harbor core OIDC 环境 =="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data}' | python3 -c '
import sys,json
d=json.load(sys.stdin)
for k,v in d.items():
    if "OIDC" in v or "oidc" in v:
        for line in v.splitlines():
            if "OIDC" in line or "oidc" in line: print(" ", line.strip()[:140])'
echo
echo "== GitLab OIDC provider 段 =="
sed -n '55,90p' /etc/gitlab/gitlab.rb
