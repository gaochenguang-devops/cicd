#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
MV=apache-maven-3.9.9

echo "=== 1) install maven into PVC (/var/jenkins_home/tools) ==="
kubectl -n jenkins exec $POD -- bash -lc "
set -e
mkdir -p /var/jenkins_home/tools
cd /var/jenkins_home/tools
if [ ! -x $MV/bin/mvn ]; then
  echo downloading...
  curl -fsSL -o maven.tar.gz https://repo1.maven.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.tar.gz
  tar xzf maven.tar.gz && rm -f maven.tar.gz
fi
JAVA_HOME=/opt/java/openjdk $MV/bin/mvn -v | head -3
"

echo "=== 2) base image -> Harbor (eclipse-temurin:21-jre) ==="
if ! curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories/library%2Feclipse-temurin/artifacts?page_size=5' | head -c 20 | grep -q '\['; then
  podman pull docker.m.daocloud.io/library/eclipse-temurin:21-jre >/tmp/pull.log 2>&1 || tail -5 /tmp/pull.log
  podman tag docker.m.daocloud.io/library/eclipse-temurin:21-jre 192.168.200.12:30090/library/eclipse-temurin:21-jre
  podman push --tls-verify=false 192.168.200.12:30090/library/eclipse-temurin:21-jre >/tmp/push.log 2>&1 || tail -5 /tmp/push.log
  echo pushed
else
  echo "base image already in Harbor"
fi
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories?page_size=100' | python3 -c 'import sys,json;[print(" ",r["name"]) for r in json.load(sys.stdin)]'

echo "=== 3) Harbor robot robot\$jenkins-ci ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/robots?page_size=100' | grep -o '"name":"robot[^"]*"' || true
if ! curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/robots?page_size=100' | grep -q 'jenkins-ci'; then
  RESP=$(curl -s -u 'admin:__HARBOR_ADMIN_PASS__' -H 'Content-Type: application/json' -X POST \
    'http://192.168.200.12:30090/api/v2.0/robots' \
    -d '{"name":"jenkins-ci","description":"Jenkins 流水线推镜像","level":"project","permissions":[{"kind":"project","namespace":"apps","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]}]}')
  echo "$RESP" | head -c 500; echo
else
  echo "robot already exists"
fi
