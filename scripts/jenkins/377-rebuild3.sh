#!/bin/bash
set -uo pipefail
cd /root/jenkins-src/shared-library
git add -A
git -c user.email=ci@corp.local -c user.name=cicd-bot commit -q -m "fix: Jib 用无前缀系统属性 sendCredentialsOverHttp（HTTP registry 才肯发凭据）" || true
git push -q origin main
echo "lib HEAD=$(git rev-parse --short HEAD)"

J='http://192.168.200.12:30088'; AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/j9; rm -f $CK
C=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $C" -o /dev/null -w 'trigger=%{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
