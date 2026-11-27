#!/bin/bash
set -uo pipefail
IMG=harbor.corp.local/library/jenkins:lts-jdk21
mkdir -p /root/cacerts-build/jenkins /root/cacerts-build/sonar
cp /root/gateway-tls/ca.crt /root/cacerts-build/ca.crt

podman pull -q "$IMG" >/dev/null 2>&1 || true

echo "=== 生成 jenkins cacerts（原 keystore + 内部 CA） ==="
kubectl -n jenkins get secret jenkins-java-cacerts -o jsonpath='{.data.cacerts}' | base64 -d > /root/cacerts-build/jenkins/cacerts
podman run --rm -v /root/cacerts-build:/w "$IMG" sh -c '
keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca -file /w/ca.crt \
  -keystore /w/jenkins/cacerts -storepass changeit 2>&1 | tail -2
keytool -list -keystore /w/jenkins/cacerts -storepass changeit 2>/dev/null | grep -i "corp-internal-ca"
'

echo "=== 生成 sonar cacerts ==="
kubectl -n sonar get secret sonar-java-cacerts -o jsonpath='{.data.cacerts}' | base64 -d > /root/cacerts-build/sonar/cacerts
podman run --rm -v /root/cacerts-build:/w "$IMG" sh -c '
keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca -file /w/ca.crt \
  -keystore /w/sonar/cacerts -storepass changeit 2>&1 | tail -2
keytool -list -keystore /w/sonar/cacerts -storepass changeit 2>/dev/null | grep -i "corp-internal-ca"
'

echo "=== 回写 Secret ==="
kubectl -n jenkins create secret generic jenkins-java-cacerts --from-file=cacerts=/root/cacerts-build/jenkins/cacerts --dry-run=client -o yaml | kubectl apply -f - >/dev/null && echo "  jenkins secret 更新"
kubectl -n sonar create secret generic sonar-java-cacerts --from-file=cacerts=/root/cacerts-build/sonar/cacerts --dry-run=client -o yaml | kubectl apply -f - >/dev/null && echo "  sonar secret 更新"
