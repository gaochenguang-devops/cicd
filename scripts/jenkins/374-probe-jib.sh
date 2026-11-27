#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
echo "pod=$POD"
kubectl -n jenkins exec -i "$POD" -- bash -c 'ls /var/jenkins_home/workspace/ 2>/dev/null; ls /var/jenkins_home/workspace/maven-demo-pipeline/target/*.jar 2>/dev/null'

echo "=== 测试 B: jib.container.sendCredentialsOverHttp ==="
kubectl -n jenkins exec -i "$POD" -- bash -c '
cd /var/jenkins_home/workspace/maven-demo-pipeline || exit 1
/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn -B -ntp -DskipTests jib:build \
  -Djib.allowInsecureRegistries=true \
  -Djib.container.sendCredentialsOverHttp=true \
  -Djib.from.image=192.168.200.12:30090/library/eclipse-temurin:21-jre \
  -Djib.from.auth.username="robot\$library+jenkins-lib-pull" \
  -Djib.from.auth.password=__HARBOR_ROBOT_LIB_SECRET__ \
  -Djib.to.image=192.168.200.12:30090/apps/maven-demo \
  -Djib.to.tags=probe1 \
  -Djib.to.auth.username="robot\$apps+jenkins-ci" \
  -Djib.to.auth.password=__HARBOR_ROBOT_JENKINS_SECRET__ 2>&1 | tail -25
'
