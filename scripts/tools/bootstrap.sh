#!/usr/bin/env bash
# bootstrap.sh —— 在目标服务器（192.168.200.12）上按顺序执行全部部署脚本
# 用法: 把 scripts 目录整体拷到服务器后执行  bash tools/bootstrap.sh
# 说明: 每个脚本失败不中断，最后统一汇总；所有脚本均可重跑
set -uo pipefail
cd "$(dirname "$0")/.."

STEPS=(
  probe/probe.sh
  k8s/01-prepare.sh
  k8s/02-precheck-images.sh
  k8s/03-kubeadm-init.sh
  k8s/04-cni.sh
  argocd/05-argocd.sh
  gitlab/08-gitlab-rpm.sh
  gitlab/09-gitlab-wait.sh
  gitlab/10-gitlab-init.sh
  gitlab/11-demo-repo.sh
  argocd/12-argocd-connect.sh
  argocd/15-webhook-diag.sh
  argocd/16-webhook-verify.sh
  argocd/17-final.sh
)

FAILED=()
for s in "${STEPS[@]}"; do
  [ -f "$s" ] || { echo "SKIP missing $s"; continue; }
  echo ""
  echo "#################### $s ####################"
  if ! bash "$s"; then
    FAILED+=("$s")
    echo "!!!!! $s FAILED (继续执行后续步骤)"
  fi
done

echo ""
echo "#################### 汇总 ####################"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "全部步骤执行成功"
else
  for f in "${FAILED[@]}"; do echo "FAILED: $f"; done
fi
echo "注意：18-enable-and-reboot.sh 会重启机器，未纳入自动流程，需要时手动执行。"
