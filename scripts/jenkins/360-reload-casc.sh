#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/jck; rm -f $CK

CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
echo "crumb=${CRUMB:0:12}..."

code=$(curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /tmp/reload.txt -w '%{http_code}' -X POST "$J/configuration-as-code/reload")
echo "reload http=$code"
head -c 400 /tmp/reload.txt; echo

sleep 5
echo "=== whoAmI (breakglass 仍可用?) ==="
curl -s -u "$AU" "$J/whoAmI/api/json" | head -c 300; echo
echo "=== credentials ==="
curl -s -u "$AU" "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName,description]" | python3 -m json.tool 2>/dev/null | head -40
echo "=== global libraries ==="
kubectl -n jenkins logs deploy/jenkins --tail=80 | grep -iE 'library|shared|casc|error' | tail -15
