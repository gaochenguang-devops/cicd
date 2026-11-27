#!/usr/bin/env bash
set -uo pipefail
echo "== Harbor configurations（认证相关） =="
curl -s -u admin:'__HARBOR_ADMIN_PASS__' 'http://127.0.0.1:30090/api/v2.0/configurations' \
 | python3 -c '
import sys,json
d=json.load(sys.stdin)
for k in ["auth_mode","oidc_name","oidc_endpoint","oidc_client_id","oidc_groups_claim","oidc_scope","oidc_auto_onboard","oidc_user_claim","self_registration","project_creation_restriction","robot_token_expiration","token_expiration"]:
    if k in d: print(" ",k,"=",d[k])'
echo
echo "== Sonar / Artifactory 资源配额 =="
kubectl -n sonar get deploy -o json | python3 -c '
import sys,json
for it in json.load(sys.stdin)["items"]:
    c=it["spec"]["template"]["spec"]["containers"][0]
    print(" ",it["metadata"]["name"],"image=",c["image"],"resources=",c.get("resources"))'
kubectl -n artifactory get deploy -o json | python3 -c '
import sys,json
for it in json.load(sys.stdin)["items"]:
    c=it["spec"]["template"]["spec"]["containers"][0]
    print(" ",it["metadata"]["name"],"image=",c["image"],"resources=",c.get("resources"))'
echo
echo "== 镜像清单（全部业务 Pod） =="
kubectl get pod -A -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | sort -u | grep -v '^$'
