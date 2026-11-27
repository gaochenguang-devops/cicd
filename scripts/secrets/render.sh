#!/bin/bash
# 把文档里的 __VAR__ 占位符按 .env 渲染到临时副本（用于本地复现命令）
# 用法：bash scripts/secrets/render.sh docs/01-入口与网络/访问层与证书.md > /tmp/rendered.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:?用法: render.sh <file>}"
[ -f "$ROOT/.env" ] || { echo "缺少 $ROOT/.env（先 cp .env.example .env 并填值）" >&2; exit 1; }
set -a; . "$ROOT/.env"; set +a
OUT="$(cat "$SRC")"
while IFS='=' read -r k v; do
  [ -z "$k" ] && continue
  case "$k" in \#*) continue;; esac
  OUT="${OUT//__${k}__/$v}"
done < "$ROOT/.env"
printf '%s\n' "$OUT"

