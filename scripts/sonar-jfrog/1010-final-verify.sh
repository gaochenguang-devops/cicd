#!/usr/bin/env bash
set -uo pipefail
T=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
U="http://127.0.0.1:30092/artifactory/build-artifacts/podinfo/main/$T"
cd /tmp && rm -rf av && mkdir av && cd av
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' -O "$U/podinfo-$T.tar.gz"
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' -O "$U/podinfo-$T.tar.gz.sha256"
echo "remote sha = $(cat podinfo-$T.tar.gz.sha256)"
echo "local  sha = $(sha256sum podinfo-$T.tar.gz | awk '{print $1}')"
[ "$(cat podinfo-$T.tar.gz.sha256)" = "$(sha256sum podinfo-$T.tar.gz | awk '{print $1}')" ] && echo "SHA256 OK" || echo "SHA256 MISMATCH"
tar tzf "podinfo-$T.tar.gz"
echo "== 目录清单 =="
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' "http://127.0.0.1:30092/artifactory/api/storage/build-artifacts/podinfo/main/$T" | python3 -c '
import sys,json;d=json.load(sys.stdin)
for c in d.get("children",[]): print(" ",c["uri"],c.get("size"))'
