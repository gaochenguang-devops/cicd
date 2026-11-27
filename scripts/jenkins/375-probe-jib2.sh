#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
echo "pod=$POD"

kubectl -n jenkins exec -i "$POD" -- bash -c '
set -e
rm -rf /tmp/jibtest && git clone -q http://root:__GITLAB_PAT__@192.168.200.12/root/demo-maven.git /tmp/jibtest
cd /tmp/jibtest
MVN=/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn
$MVN -q -B -ntp -DskipTests package 2>&1 | tail -3
echo "--- 变体1: -Djib.container.sendCredentialsOverHttp=true"
$MVN -B -ntp -DskipTests jib:build -Djib.allowInsecureRegistries=true -Djib.container.sendCredentialsOverHttp=true \
 -Djib.from.image=192.168.200.12:30090/library/eclipse-temurin:21-jre \
 -Djib.from.auth.username="robot\$library+jenkins-lib-pull" -Djib.from.auth.password=__HARBOR_ROBOT_LIB_SECRET__ \
 -Djib.to.image=192.168.200.12:30090/apps/maven-demo -Djib.to.tags=probe1 \
 -Djib.to.auth.username="robot\$apps+jenkins-ci" -Djib.to.auth.password=__HARBOR_ROBOT_JENKINS_SECRET__ 2>&1 | grep -E "ERROR|BUILD|credentials|manifest" | head -12
'
