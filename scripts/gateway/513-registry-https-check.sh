#!/bin/bash
set -uo pipefail
echo "=== containerd 配置里的 registry 相关 ==="
ls -1 /etc/containerd/certs.d/ 2>/dev/null || echo "  (无 certs.d 目录)"
grep -nE "insecure|mirror|config_path|registry" /etc/containerd/config.toml | head -20
echo
echo "=== 现有 Harbor 项目/镜像（admin，走 https） ==="
curl -s -k -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects?page_size=20" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  ", [ (p["name"],p.get("registry_id")) for p in d])' 2>&1 | head -3
for p in apps library; do
  echo "--- project $p repositories"
  curl -s -k -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects/$p/repositories?page_size=20" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  ", [r["name"] for r in d])' 2>&1 | head -3
done
echo
echo "=== podman login/push 到 harbor.corp.local ==="
echo '__HARBOR_ADMIN_PASS__' | podman login -u admin --password-stdin harbor.corp.local 2>&1 | tail -1
podman pull -q docker.io/library/busybox:latest >/dev/null 2>&1 || true
podman tag docker.io/library/busybox:latest harbor.corp.local/library/probe-https:20261127 2>/dev/null
podman push harbor.corp.local/library/probe-https:20261127 2>&1 | tail -3
echo
echo "=== 节点上 crictl 直接拉 https 域名镜像 ==="
crictl pull harbor.corp.local/library/probe-https:20261127 2>&1 | tail -3
