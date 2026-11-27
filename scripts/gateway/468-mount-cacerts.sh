#!/bin/bash
set -uo pipefail
echo "===== 挂载 cacerts（Jenkins） ====="
kubectl -n jenkins patch deploy jenkins --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"secretName":"jenkins-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]'
echo "===== 挂载 cacerts（Sonar） ====="
kubectl -n sonar patch deploy sonarqube --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"secretName":"sonar-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]'
sleep 20
kubectl -n jenkins get pods; kubectl -n sonar get pods
echo "=== 验证容器内 truststore 是否含 corp CA（Jenkins 需等 Ready） ==="
JP=$(kubectl -n jenkins get pod -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' | awk '$2=="true"{print $1}' | head -1)
echo "  jenkins ready pod=$JP"
[ -n "$JP" ] && kubectl -n jenkins exec $JP -- sh -c '/opt/java/openjdk/bin/keytool -list -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i corp' 2>&1 | head -3
SP=$(kubectl -n sonar get pod -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' | awk '$2=="true"{print $1}' | grep sonarqube | head -1)
echo "  sonar ready pod=$SP"
[ -n "$SP" ] && kubectl -n sonar exec $SP -c sonarqube -- sh -c '/opt/java/openjdk/bin/keytool -list -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit 2>/dev/null | grep -i corp' 2>&1 | head -3
