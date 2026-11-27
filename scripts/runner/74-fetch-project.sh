#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"
TOKEN="__GITLAB_PAT__"
echo "== 从 GitHub 取 Podinfo（服务器不能直连 github.com，走 gh-proxy）=="
rm -rf /tmp/podinfo-src
for u in "https://gh-proxy.com/https://github.com/stefanprodan/podinfo/archive/refs/heads/master.tar.gz" \
         "https://gh-proxy.com/https://raw.githubusercontent.com/stefanprodan/podinfo/master/README.md"; do
  printf "  %-80s " "${u:0:80}"; curl -s -o /dev/null -m 15 -w "%{http_code}\n" "$u"
done
curl -sSL -m 60 -o /tmp/podinfo.tar.gz "https://gh-proxy.com/https://github.com/stefanprodan/podinfo/archive/refs/heads/master.tar.gz"
ls -lh /tmp/podinfo.tar.gz
tar -xzf /tmp/podinfo.tar.gz -C /tmp && mv /tmp/podinfo-master /tmp/podinfo-src
cd /tmp/podinfo-src
echo
echo "== 仓库结构 =="
ls
echo "--- 关键文件 ---"
ls Dockerfile Makefile go.mod ui/package.json .github/workflows 2>/dev/null
echo
echo "== 版本与构建方式 =="
head -3 go.mod; grep -E "^VERSION|^BASE|GO_VERSION" Makefile | head -5
sed -n '1,30p' Dockerfile
echo
echo "== 代码规模 =="
echo "go 文件: $(find . -name '*.go' | wc -l), ui 源文件: $(find ui/src -type f 2>/dev/null | wc -l), 总大小: $(du -sh . | cut -f1)"
