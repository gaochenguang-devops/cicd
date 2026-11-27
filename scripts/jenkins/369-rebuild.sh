#!/bin/bash
set -uo pipefail
PAT='__GITLAB_PAT__'
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
cd /root/jenkins-src/demo-maven
git add -A && git -c user.email=ci@corp.local -c user.name=cicd-bot commit -q -m "fix: 去掉 timestamps()（timestamper 插件未安装）"
git push -q origin main && echo "pushed $(git rev-parse --short HEAD)"

CK=/tmp/jck6; rm -f $CK
CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /dev/null -w 'trigger=%{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
