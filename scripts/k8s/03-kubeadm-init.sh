#!/bin/bash
set -uo pipefail
cat >/root/kubeadm-config.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  name: pxe-boot-test-1
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: kubernetes
kubernetesVersion: v1.32.13
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
podSubnet: 10.244.0.0/16
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
EOF
cat /root/kubeadm-config.yaml
echo "=== kubeadm init ==="
kubeadm init --config /root/kubeadm-config.yaml --ignore-preflight-errors=Swap 2>&1 | tee /root/kubeadm-init.log | tail -45
echo "RC=${PIPESTATUS[0]}"
