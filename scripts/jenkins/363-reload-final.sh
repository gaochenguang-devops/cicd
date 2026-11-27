#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')

echo "=== pod 内 casc 文件 ==="
kubectl -n jenkins exec $POD -- bash -lc 'ls -l /var/jenkins_home/casc/; echo ---; grep -nE "harbor-jenkins-ci|platform-lib|globalLibraries|credentials:" /var/jenkins_home/casc/jenkins.yaml | head -20'

CK=/tmp/jck4; rm -f $CK
CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
code=$(curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /tmp/r3.txt -w '%{http_code}' -X POST "$J/configuration-as-code/reload")
echo "reload=$code"; head -c 300 /tmp/r3.txt; echo
sleep 6
echo "=== credentials ==="
curl -s -u "$AU" "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName]" | head -c 800; echo
echo "=== JCasC 应用日志 ==="
kubectl -n jenkins logs deploy/jenkins --tail=60 | grep -iE 'casc|credential|library|suppress|error' | tail -12
