#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/jck5; rm -f $CK
CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')

cat > /tmp/job.xml <<'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>平台标准流水线：代码拉取 → Sonar 扫描 → Maven 打包 → Jib 构建镜像 → 推送 JFrog（逻辑在 platform-lib 共享库）</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>http://192.168.200.12/root/demo-maven.git</url>
          <credentialsId>gitlab-pat</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML

code=$(curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -H 'Content-Type: application/xml' \
  --data-binary @/tmp/job.xml -o /tmp/create.txt -w '%{http_code}' "$J/createItem?name=maven-demo-pipeline")
echo "createItem=$code"
head -c 200 /tmp/create.txt; echo

if [ "$code" != "200" ]; then
  echo "=== 已存在则更新 config.xml ==="
  curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -H 'Content-Type: application/xml' \
    --data-binary @/tmp/job.xml -o /dev/null -w 'update=%{http_code}\n' "$J/job/maven-demo-pipeline/config.xml"
fi

echo "=== 触发 #1 ==="
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /dev/null -w 'build=%{http_code}\n' -X POST "$J/job/maven-demo-pipeline/build"
sleep 12
curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result,duration" ; echo
