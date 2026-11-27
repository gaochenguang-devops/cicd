#!/bin/bash
set -uo pipefail
echo "=== 各 registry 可达性（HEAD /v2/） ==="
for H in quay.io ghcr.io registry.k8s.io docker.io docker.m.daocloud.io quay.m.daocloud.io ghcr.m.daocloud.io registry.k8s.io; do
  code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "https://$H/v2/" 2>/dev/null)
  echo "  $H -> ${code:-timeout}"
done
echo "=== 已有镜像里是否已存在（Harbor library） ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories?page_size=50' \
 | python3 -c 'import sys,json
for r in json.load(sys.stdin): print("  ",r["name"])'
echo "=== podman 现有镜像 ==="
podman images --format '{{.Repository}}:{{.Tag}}' | head -20
