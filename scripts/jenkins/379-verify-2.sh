#!/bin/bash
set -uo pipefail
echo "=== Artifactory 重新列目录（无缓存） ==="
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/api/storage/build-artifacts/maven-demo/main/1.0.6/?list" | python3 -m json.tool 2>/dev/null | head -40
echo "=== 各文件 HEAD 校验 ==="
for f in maven-demo.jar maven-demo.jar.sha256 build-info.json; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -I -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/1.0.6/$f")
  echo "  $f -> $code"
done
echo "=== 集群内 imagePullSecret 情况 ==="
kubectl -n default get secrets 2>/dev/null | grep -i -E 'harbor|registry' || echo "  default 无 registry secret"
kubectl -n apps get deploy podinfo -o jsonpath='{.spec.template.spec.imagePullSecrets}' 2>/dev/null; echo
