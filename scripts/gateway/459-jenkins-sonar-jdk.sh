#!/bin/bash
set -uo pipefail
echo "########## Jenkins deployment 关键片段 ##########"
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].env}'; echo
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.volumes}'; echo
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
echo "########## Jenkins 容器里 JDK / 是否可写 cacerts ##########"
kubectl -n jenkins exec deploy/jenkins -- sh -c 'echo JAVA_HOME=$JAVA_HOME; ls -l $JAVA_HOME/lib/security/cacerts 2>/dev/null; id' 2>&1 | head -6
echo "########## Sonar 容器 JDK / keytool ##########"
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'echo JAVA_HOME=$JAVA_HOME; command -v keytool || ls /opt/java/*/bin/keytool 2>/dev/null; ls -l $JAVA_HOME/lib/security/cacerts' 2>&1 | head -6
