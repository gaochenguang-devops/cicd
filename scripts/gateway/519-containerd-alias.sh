#!/bin/bash
set -uo pipefail
echo "=== 先看 harbor-registry 的 token realm（是否已随 EXT_ENDPOINT 变成域名） ==="
kubectl -n harbor exec deploy/harbor-registry -c registry -- cat /etc/registry/config.yml 2>/dev/null | grep -A4 'auth:' | head -8
echo
echo "=== containerd 侧：给 192.168.200.12:30090 做 https 域名别名 ==="
mkdir -p /etc/containerd/certs.d/192.168.200.12:30090
cat > /etc/containerd/certs.d/192.168.200.12:30090/hosts.toml <<'EOF'
# 镜像名仍写 192.168.200.12:30090，实际走 https://harbor.corp.local（网关 TLS）
server = "https://harbor.corp.local"

[host."https://harbor.corp.local"]
  capabilities = ["pull", "resolve"]
  ca = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
EOF
systemctl restart containerd
sleep 8
echo "--- 用 IP 名拉私有镜像复测 ---"
crictl pull 192.168.200.12:30090/apps/podinfo:dfa6136fc7d0c0ff825c33d74aaa38ad818c13d4 2>&1 | tail -3
echo "--- 拉一个本地没缓存的镜像（redis）验证真走了远端 ---"
crictl rmi 192.168.200.12:30090/apps/redis:7-alpine >/dev/null 2>&1
crictl pull 192.168.200.12:30090/apps/redis:7-alpine 2>&1 | tail -3
