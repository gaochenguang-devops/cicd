#!/usr/bin/env sh
# 安装仓库内的 git hooks（.githooks/），Linux / macOS / Windows(Git Bash) 通用
set -eu
root=$(git rev-parse --show-toplevel)
cd "$root"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push 2>/dev/null || true

echo "[hooks] core.hooksPath = $(git config core.hooksPath)"
echo "[hooks] 已启用: pre-commit（挡 .env / 明文凭据）、pre-push（扫历史）"
echo "[hooks] 复查: git config --get core.hooksPath；临时跳过: git commit --no-verify"
