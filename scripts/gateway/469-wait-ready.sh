#!/bin/bash
set -uo pipefail
echo "=== 当前挂载 ==="
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
kubectl -n sonar get deploy sonarqube -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.volumes}'; echo
echo "=== 等待就绪 ==="
kubectl -n jenkins rollout status deploy/jenkins --timeout=240s | tail -1
kubectl -n sonar rollout status deploy/sonarqube --timeout=240s | tail -1
echo "=== CA 是否进 truststore ==="
JP=$(kubectl -n jenkins get pod -o name | grep -v Terminating | head -1)
kubectl -n jenkins exec $JP -- sh -c '/opt/java/openjdk/bin/keytool -list -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i corp' 2>&1 | head -3
SP=$(kubectl -n sonar get pod -o name | grep sonarqube | head -1)
kubectl -n sonar exec $SP -c sonarqube -- sh -c '/opt/java/openjdk/bin/keytool -list -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i corp' 2>&1 | head -3
