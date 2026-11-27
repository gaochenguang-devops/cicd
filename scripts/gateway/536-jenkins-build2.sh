#!/bin/bash
set -uo pipefail
J=https://jenkins.corp.local
CRUMB=$(curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
echo "[crumb] $CRUMB"
curl -s -k -o /dev/null -w '触发: %{http_code}\n' -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' \
  -H "Jenkins-Crumb: $CRUMB" -X POST "$J/job/maven-demo-pipeline/build"
sleep 20
for i in $(seq 1 25); do
  B=$(curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result")
  N=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
  R=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"])')
  BI=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["building"])')
  echo "[$((i*10+20))s] build #$N building=$BI result=$R"
  [ "$BI" = "False" ] && [ "$N" -ge 8 ] && break
done
echo "=== 关键日志（jib / 镜像地址 / 门禁） ==="
curl -s -k -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' "$J/job/maven-demo-pipeline/lastBuild/consoleText" | grep -iE "jib|harbor.corp.local|manifest_http|已推送到|Attempting again with HTTP|ERROR|Finished:" | tail -15
