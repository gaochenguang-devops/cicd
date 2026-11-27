#!/bin/bash
set -uo pipefail
P=$(kubectl -n jenkins get pod -o name | head -1)
echo "=== jenkins keystore 中精确找内部 CA ==="
kubectl -n jenkins exec $P -c jenkins -- sh -c 'keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i "corp internal"' || echo "  未找到 CORP Internal CA"
echo "=== Secret jenkins-java-cacerts 更新时间 ==="
kubectl -n jenkins get secret jenkins-java-cacerts -o jsonpath='{.metadata.creationTimestamp}{"\n"}'
echo "=== sonar keystore 抽查 ==="
SP=$(kubectl -n sonar get pod -o name | grep sonarqube | head -1)
kubectl -n sonar exec $SP -- sh -c 'keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i "corp internal"' || echo "  sonar 未找到"
