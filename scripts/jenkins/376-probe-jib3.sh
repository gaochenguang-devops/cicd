#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
kubectl -n jenkins exec -i "$POD" -- bash -c '
cd /tmp/jibtest || exit 1
MVN=/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn
echo "--- 变体2: -DsendCredentialsOverHttp=true"
$MVN -B -ntp -DskipTests jib:build -DsendCredentialsOverHttp=true -Djib.allowInsecureRegistries=true \
 -Djib.from.image=192.168.200.12:30090/library/eclipse-temurin:21-jre \
 -Djib.from.auth.username="robot\$library+jenkins-lib-pull" -Djib.from.auth.password=__HARBOR_ROBOT_LIB_SECRET__ \
 -Djib.to.image=192.168.200.12:30090/apps/maven-demo -Djib.to.tags=probe1 \
 -Djib.to.auth.username="robot\$apps+jenkins-ci" -Djib.to.auth.password=__HARBOR_ROBOT_JENKINS_SECRET__ 2>&1 | tail -14
'
