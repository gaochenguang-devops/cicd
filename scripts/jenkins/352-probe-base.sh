#!/bin/bash
set -uo pipefail
echo "=== host: podman & docker.io ==="
which podman docker 2>/dev/null
podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | head -20
curl -s -o /dev/null -w 'dockerhub=%{http_code}\n' --max-time 8 https://registry-1.docker.io/v2/ || echo dockerhub-fail
echo "=== pod: dockerhub ==="
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
kubectl -n jenkins exec $POD -- bash -lc "curl -s -o /dev/null -w 'pod-dockerhub=%{http_code}\n' --max-time 8 https://registry-1.docker.io/v2/"
echo "=== harbor library repos ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories?page_size=50' | python3 -c 'import sys,json;[print(r["name"]) for r in json.load(sys.stdin)]' 2>/dev/null
echo "=== harbor robots raw ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/robots?page_size=50' | head -c 600; echo
echo "=== gitlab namespaces / current user ==="
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/user' | head -c 300; echo
echo "=== sonar scanner from maven central reachable? ==="
curl -s -o /dev/null -w 'sonar-plugin=%{http_code}\n' --max-time 8 https://repo1.maven.org/maven2/org/sonarsource/scanner/maven/sonar-maven-plugin/maven-metadata.xml
echo "=== apache maven tarball ==="
curl -s -o /dev/null -w 'maven-tgz=%{http_code}\n' --max-time 8 https://repo1.maven.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.tar.gz
