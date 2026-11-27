#!/usr/bin/env bash
set -uo pipefail
echo "=== 修复开机自启 ==="
systemctl enable kubelet
systemctl enable containerd
systemctl enable gitlab-runsvdir
systemctl enable sshd
echo "--- 自启状态 ---"
for s in containerd kubelet gitlab-runsvdir sshd; do echo -n "$s: "; systemctl is-enabled $s; done

echo "=== 验证 kubelet 配置（swap 放行）==="
grep -E "failSwapOn|cgroupDriver" /var/lib/kubelet/config.yaml
cat /var/lib/kubelet/kubeadm-flags.env

echo "=== 记录当前部署快照 ==="
export KUBECONFIG=/root/.kube/config
kubectl get nodes
kubectl -n argocd get app demo-app

echo "=== 重启服务器（验证自启，约 4-6 分钟）==="
(sleep 3; systemctl reboot) >/dev/null 2>&1 &
echo "reboot scheduled"
