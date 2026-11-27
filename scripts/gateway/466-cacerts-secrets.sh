#!/bin/bash
set -uo pipefail
CA=/root/gateway-tls/ca.crt
echo "===== 1. 复查 DNS（重试） ====="
kubectl -n gateway exec deploy/gateway -- nslookup keycloak.corp.local 10.96.0.10 2>&1 | tail -4

echo "===== 2. Jenkins / Sonar 现在的状态 ====="
kubectl -n jenkins get pods
kubectl -n sonar get pods

echo "===== 3. 用临时 Pod 生成带内部 CA 的 cacerts（Jenkins 镜像） ====="
kubectl -n jenkins run cacerts-jenkins --image=192.168.200.12:30090/library/jenkins:lts-jdk21 \
  --restart=Never --command -- sleep 600 >/dev/null 2>&1
kubectl -n jenkins wait --for=condition=Ready pod/cacerts-jenkins --timeout=90s | tail -1
kubectl -n jenkins cp $CA cacerts-jenkins:/tmp/corp-ca.crt
kubectl -n jenkins exec cacerts-jenkins -- sh -c '
JAVA_HOME=/opt/java/openjdk
cp $JAVA_HOME/lib/security/cacerts /tmp/cacerts-corp
$JAVA_HOME/bin/keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca \
  -file /tmp/corp-ca.crt -keystore /tmp/cacerts-corp -storepass changeit 2>&1 | tail -2'
kubectl -n jenkins cp cacerts-jenkins:/tmp/cacerts-corp /tmp/cacerts-jenkins
kubectl -n jenkins create secret generic jenkins-java-cacerts --from-file=cacerts=/tmp/cacerts-jenkins --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
kubectl -n jenkins delete pod cacerts-jenkins --now >/dev/null 2>&1

echo "===== 4. 同法生成 Sonar 的 cacerts ====="
kubectl -n sonar run cacerts-sonar --image=192.168.200.12:30090/library/sonarqube:10.7-community \
  --restart=Never --command -- sleep 600 >/dev/null 2>&1
kubectl -n sonar wait --for=condition=Ready pod/cacerts-sonar --timeout=90s | tail -1
kubectl -n sonar cp $CA cacerts-sonar:/tmp/corp-ca.crt
kubectl -n sonar exec cacerts-sonar -- sh -c '
JAVA_HOME=/opt/java/openjdk
cp $JAVA_HOME/lib/security/cacerts /tmp/cacerts-corp
$JAVA_HOME/bin/keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca \
  -file /tmp/corp-ca.crt -keystore /tmp/cacerts-corp -storepass changeit 2>&1 | tail -2'
kubectl -n sonar cp cacerts-sonar:/tmp/cacerts-corp /tmp/cacerts-sonar
kubectl -n sonar create secret generic sonar-java-cacerts --from-file=cacerts=/tmp/cacerts-sonar --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
kubectl -n sonar delete pod cacerts-sonar --now >/dev/null 2>&1

echo "===== 5. 重新挂载（用 Secret 覆盖默认 cacerts 文件） ====="
kubectl -n jenkins patch deploy jenkins --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"secretName":"jenkins-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]' | tail -1
kubectl -n sonar patch deploy sonarqube --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"name":"sonar-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]' | tail -1
