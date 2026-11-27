#!/bin/bash
set -uo pipefail
echo "=== namespaces ==="
kubectl get ns
echo "=== podinfo 在哪 ==="
kubectl get deploy -A | grep -i podinfo
echo "=== containerd 对 Harbor 的认证配置 ==="
ls /etc/containerd/certs.d/ 2>/dev/null
cat /etc/containerd/certs.d/192.168.200.12:30090/hosts.toml 2>/dev/null || echo "  无 hosts.toml"
grep -n -A6 '192.168.200.12:30090' /etc/containerd/config.toml 2>/dev/null | head -30 || echo "  config.toml 无该 registry 段"
grep -rn 'auth' /etc/containerd/config.toml 2>/dev/null | head -5
