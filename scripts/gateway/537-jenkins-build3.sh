#!/bin/bash
set -uo pipefail
J=https://jenkins.corp.local
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/jck2.txt
C=$(curl -s -k -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
echo "[crumb] ok"
curl -s -k -b $CK -u "$AU" -H "Jenkins-Crumb: $C" -o /dev/null -w '触发 build: %{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
sleep 20
for i in $(seq 1 22); do
  B=$(curl -s -k -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result")
  N=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
  R=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"])')
  BI=$(echo "$B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["building"])')
  echo "[$((i*10+20))s] build #$N building=$BI result=$R"
  [ "$BI" = "False" ] && [ "$N" -ge 8 ] && break
done
echo "=== 关键日志 ==="
curl -s -k -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/consoleText" | grep -iE "jib.to.image|jib.from.image|Attempting again with HTTP|manifest_http|已推送到|Finished:" | tail -12
