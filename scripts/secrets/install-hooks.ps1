# 安装仓库内的 git hooks（.githooks/）—— Windows / PowerShell 版
$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel).Trim()
Set-Location $root

git config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw "git config 失败" }

Write-Host "[hooks] core.hooksPath = $((git config core.hooksPath).Trim())"
Write-Host "[hooks] 已启用: pre-commit（挡 .env / 明文凭据）、pre-push（扫历史）"
Write-Host "[hooks] 复查: git config --get core.hooksPath   临时跳过: git commit --no-verify"
Write-Host "[hooks] 注意: Git for Windows 用自带的 sh 执行 hook，python 需在 PATH 里（没有则退化为 grep 兜底）"
