#!/bin/bash
# 01-prepare.sh  系统准备：swap、内核参数、containerd 安装与镜像加速
set -euo pipefail
echo "########## 1. 停止失败的 kubelet（缺容器运行时导致）"
systemctl stop kubelet 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true

echo "########## 2. 配置 4G swap（7G 物理内存跑 GitLab+K8s 需要兜底）"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
swapon --show
free -m | head -3

echo "########## 3. 内核模块与 sysctl"
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "########## 4. 添加 docker-ce 仓库（阿里云镜像，含 el10 的 containerd.io）"
cat >/etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/10/$basearch/stable
enabled=1
gpgcheck=0
EOF
dnf makecache >/dev/null 2>&1 || true
dnf install -y containerd.io 2>&1 | tail -5

echo "########## 5. 生成 containerd 配置：SystemdCgroup + sandbox 镜像 + docker.io 加速"
mkdir -p /etc/containerd
if [ -f /etc/containerd/config.toml ]; then
  cp -a /etc/containerd/config.toml /etc/containerd/config.toml.bak.$(date +%s)
fi
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.10"#' /etc/containerd/config.toml

# docker.io 走 DaoCloud 加速（服务器直连 Docker Hub 不通）
python3 - <<'PY' 2>/dev/null || true
import re
p="/etc/containerd/config.toml"
s=open(p).read()
if 'docker.m.daocloud.io' not in s:
    s=s.replace('[plugins."io.containerd.grpc.v1.cri".registry]',
    '[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n  endpoint = ["https://docker.m.daocloud.io"]\n\n[plugins."io.containerd.grpc.v1.cri".registry]',1)
open(p,"w").write(s)
PY

echo "########## 6. 启动 containerd"
systemctl enable --now containerd
mkdir -p /etc
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 20
debug: false
EOF
sleep 3
systemctl is-active containerd
containerd --version

echo "########## 7. 验证拉取 k8s pause 镜像"
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.10 && echo "PULL-PAUSE-OK"
crictl images | head -10
echo "########## PREPARE DONE"
