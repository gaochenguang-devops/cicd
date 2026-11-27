#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/j8; rm -f $CK
C=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $C" -o /dev/null -w 'trigger=%{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
echo "queue/last:"
curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result,duration"; echo
