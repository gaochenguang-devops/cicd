#!/bin/bash
set -uo pipefail
mkdir -p /etc/containerd/certs.d/harbor.corp.local
cat > /etc/containerd/certs.d/harbor.corp.local/hosts.toml <<'EOF'
server = "https://harbor.corp.local"

[host."https://harbor.corp.local"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
EOF
cat /etc/containerd/certs.d/harbor.corp.local/hosts.toml
systemctl restart containerd
sleep 8
kubectl get nodes | tail -2
echo "=== crictl pull 复测 ==="
crictl pull harbor.corp.local/library/probe-https:20261127 2>&1 | tail -2
