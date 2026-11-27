#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
cd /root/jenkins-src/shared-library
git add -A && git -c user.email=ci@corp.local -c user.name=cicd-bot commit -q -m "fix: sonar 前先 compile 生成 target/classes" || true
git push -q origin main && echo "lib pushed $(git rev-parse --short HEAD)"

CK=/tmp/jck7; rm -f $CK
CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /dev/null -w 'trigger=%{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
