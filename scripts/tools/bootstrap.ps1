# 一键分步重跑（Windows 侧，通过 SSH 依次执行远端脚本）
# 用法: powershell -ExecutionPolicy Bypass -File scripts\tools\bootstrap.ps1
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here          # scripts\ 根目录，各组件脚本在此之下
$exec = Join-Path $here "ssh_exec.py"

# ssh_exec 直接执行本地脚本内容，无需先上传
$steps = @(
  "probe\probe.sh", "k8s\01-prepare.sh", "k8s\02-precheck-images.sh", "k8s\03-kubeadm-init.sh",
  "k8s\04-cni.sh", "argocd\05-argocd.sh", "gitlab\08-gitlab-rpm.sh", "gitlab\09-gitlab-wait.sh",
  "gitlab\10-gitlab-init.sh", "gitlab\11-demo-repo.sh", "argocd\12-argocd-connect.sh",
  "argocd\15-webhook-diag.sh", "argocd\16-webhook-verify.sh", "argocd\17-final.sh"
)

$failed = @()
foreach ($s in $steps) {
  Write-Output ""
  Write-Output "#################### $s ####################"
  $path = Join-Path $root $s
  if (-not (Test-Path $path)) { Write-Output "SKIP missing $s"; continue }
  python $exec --script $path --timeout 900
  if ($LASTEXITCODE -ne 0) { $failed += $s; Write-Output "!!!!! $s FAILED" }
}

Write-Output ""
Write-Output "#################### 汇总 ####################"
if ($failed.Count -eq 0) { Write-Output "全部步骤执行成功" } else { $failed | ForEach-Object { Write-Output "FAILED: $_" } }
Write-Output "注意：18-enable-and-reboot.sh 会重启机器，需手动执行。"
