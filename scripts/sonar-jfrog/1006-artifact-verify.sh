#!/usr/bin/env bash
set -uo pipefail
TAG=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
echo "deploy tag=$TAG"
echo "== 制品目录 =="
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' "http://127.0.0.1:30092/artifactory/api/storage/build-artifacts/podinfo/main" | python3 -c '
import sys,json;d=json.load(sys.stdin)
for c in d.get("children",[]): print(" ",c.get("uri"),"folder=",c.get("folder"))'
echo "== 本 tag 文件 =="
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' "http://127.0.0.1:30092/artifactory/api/storage/build-artifacts/podinfo/main/$TAG" | python3 -c '
import sys,json;d=json.load(sys.stdin)
for c in d.get("children",[]): print(" ",c.get("uri"),c.get("size"))'
echo "== 下载并校验 sha256 =="
cd /tmp && rm -rf arti-verify && mkdir arti-verify && cd arti-verify
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' -O "http://127.0.0.1:30092/artifactory/build-artifacts/podinfo/main/$TAG/podinfo-$TAG.tar.gz" \
  -O "http://127.0.0.1:30092/artifactory/build-artifacts/podinfo/main/$TAG/podinfo-$TAG.tar.gz.sha256"
sha256sum -c "podinfo-$TAG.tar.gz.sha256"
tar tzf "podinfo-$TAG.tar.gz"
