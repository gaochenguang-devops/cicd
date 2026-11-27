#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
echo "pod=$POD"
echo "=== Pod 内 JCasC 是否已是占位版 ==="
kubectl -n jenkins exec "$POD" -- grep -nE 'password|secret:' /var/jenkins_home/casc/jenkins.yaml | head -20
echo "=== Pod 内环境变量是否齐（值只打印长度） ==="
kubectl -n jenkins exec "$POD" -- bash -c 'for v in GITLAB_PAT HARBOR_CI_PASS HARBOR_LIB_PASS SONAR_TOKEN ARTI_USER ARTI_PASS OIDC_CLIENT_SECRET BREAKGLASS_PASS; do eval "val=\$$v"; echo "  $v len=${#val}"; done'

echo "=== 凭据是否加载（5 个 id） ==="
CK=/tmp/jckA; rm -f $CK
C=$(curl -s -c $CK -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' 'http://192.168.200.12:30088/crumbIssuer/api/json' | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' -H "Jenkins-Crumb: $C" \
 'http://192.168.200.12:30088/credentials/store/system/domain/_/api/json?tree=credentials%5Bid%2CtypeName%5D' \
 | python3 -c 'import sys,json;d=json.load(sys.stdin);print(" count=",len(d["credentials"]));[print("  ",c["id"],c["typeName"]) for c in d["credentials"]]'
