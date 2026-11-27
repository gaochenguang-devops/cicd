#!/bin/bash
set -uo pipefail
echo "=== base image pull/push ==="
podman pull docker.m.daocloud.io/library/eclipse-temurin:21-jre 2>&1 | tail -3
podman tag docker.m.daocloud.io/library/eclipse-temurin:21-jre 192.168.200.12:30090/library/eclipse-temurin:21-jre
podman push --tls-verify=false 192.168.200.12:30090/library/eclipse-temurin:21-jre 2>&1 | tail -3
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories?page_size=100' | python3 -c 'import sys,json;[print(" repo:",r["name"]) for r in json.load(sys.stdin)]'

echo "=== robot ==="
RESP=$(curl -s -u 'admin:__HARBOR_ADMIN_PASS__' -H 'Content-Type: application/json' -X POST \
  'http://192.168.200.12:30090/api/v2.0/robots' \
  -d '{"name":"jenkins-ci","description":"Jenkins pipeline push","level":"project","duration":-1,
       "permissions":[{"kind":"project","namespace":"apps","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]}]}')
echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("name:",d.get("name"));print("secret:",d.get("secret"));print("err:",d.get("errors"))' 2>/dev/null || echo "raw: $RESP"
