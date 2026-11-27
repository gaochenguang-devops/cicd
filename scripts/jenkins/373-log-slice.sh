#!/bin/bash
set -uo pipefail
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
J='http://192.168.200.12:30088'
N=$(curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
echo "build=$N"
curl -s -u "$AU" "$J/job/maven-demo-pipeline/$N/consoleText" | sed -n '305,352p'
