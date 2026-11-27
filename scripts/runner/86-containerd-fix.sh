#!/usr/bin/env bash
set -uo pipefail
CFG=/etc/containerd/config.toml
cp -a "$CFG" "$CFG.bak2.$(date +%s)"
python3 - "$CFG" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
out, in_reg = [], False
for ln in lines:
    if "io.containerd.cri.v1.images'.registry" in ln:
        in_reg = True
        out.append(ln); continue
    if in_reg and ln.strip().startswith('config_path'):
        out.append("      config_path = '/etc/containerd/certs.d'")
        in_reg = False; continue
    out.append(ln)
open(p, 'w').write('\n'.join(out))
PY
echo "== 修改确认 =="
sed -n '30,32p' "$CFG"
mkdir -p /etc/containerd/certs.d/docker.io
cat > /etc/containerd/certs.d/docker.io/hosts.toml <<'EOF'
server = "https://registry-1.docker.io"
[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]
EOF
ls /etc/containerd/certs.d/
systemctl restart containerd
sleep 6
systemctl is-active containerd
echo "== crictl 拉取 =="
crictl pull 192.168.200.12:30090/apps/podinfo:cb47fa84 2>&1 | tail -2
echo "== K8s 侧重试 =="
kubectl -n podinfo rollout restart deploy/podinfo deploy/redis >/dev/null 2>&1
sleep 20
kubectl -n podinfo get pods -o wide
