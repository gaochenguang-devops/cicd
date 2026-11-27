#!/bin/bash
set -uo pipefail
IRS=registry.cn-hangzhou.aliyuncs.com/google_containers
echo "=== 检查 K8s 1.32.13 控制面镜像是否在阿里云仓库 ==="
for img in kube-apiserver:v1.32.13 kube-controller-manager:v1.32.13 kube-scheduler:v1.32.13 kube-proxy:v1.32.13 etcd:3.5.16-0 coredns:v1.11.3; do
  start=$(date +%s)
  if timeout 180 crictl pull $IRS/$img >/dev/null 2>&1; then
    echo "OK   $img  ($(( $(date +%s) - start ))s)"
  else
    echo "FAIL $img"
  fi
done
echo "=== 拉取 ArgoCD / Calico 关键镜像测试 ==="
for img in quay.io/argoproj/argocd:v3.5.9 quay.io/calico/node:v3.32.3 public.ecr.aws/docker/library/redis:8.2.3-alpine ghcr.io/dexidp/dex:v2.45.1; do
  start=$(date +%s)
  if timeout 300 crictl pull $img >/dev/null 2>&1; then
    echo "OK   $img  ($(( $(date +%s) - start ))s)"
  else
    echo "FAIL $img"
  fi
done
echo "=== 本地镜像 ==="
crictl images | awk '{print $1":"$2, $4}'
