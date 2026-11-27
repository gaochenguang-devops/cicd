#!/bin/bash
set -uo pipefail
J=https://jenkins.corp.local
CRUMB=$(curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])' 2>/dev/null || echo "")
echo "[crumb] ${CRUMB:0:12}..."
curl -s -k -o /dev/null -w '触发 build: %{http_code}\n' -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' \
  ${CRUMB:+-H "Jenkins-Crumb: $CRUMB"} -X POST "$J/job/maven-demo-pipeline/build"
sleep 15
for i in $(seq 1 30); do
  sleep 10
  B=$(curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result")
  N=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
  R=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"])')
  BI=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["building"])')
  echo "[$((i*10))s] build #$N building=$BI result=$R"
  [ "$BI" = "False" ] && break
done
echo "=== 最后一个 build 的 stage 与关键日志 ==="
curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "https://jenkins.corp.local/job/maven-demo-pipeline/lastBuild/consoleText" | grep -iE "manifest_http|已推送到|ERROR|FAIL|jib" | tail -12
