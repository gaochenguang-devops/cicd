#!/usr/bin/env bash
# 镜像存在性门禁：只有 registry 里真能读到的 tag 才允许写进部署清单
# 用法：ci/verify-image.sh <registry>/<repo>:<tag>
set -euo pipefail

ref=${1:?用法: verify-image.sh <image:tag>}
tag=${ref##*:}
repo=${ref%:*}
reg=${repo%%/*}
path=${repo#*/}

: "${HARBOR_USER:?需要 HARBOR_USER}"
: "${HARBOR_PASS:?需要 HARBOR_PASS}"

ACC='Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'

code=$(curl -s -o /dev/null -w '%{http_code}' \
  -u "$HARBOR_USER:$HARBOR_PASS" -H "$ACC" \
  "http://$reg/v2/$path/manifests/$tag")

if [ "$code" != "200" ]; then
  echo "镜像不可读：$ref（registry 返回 HTTP $code），拒绝写部署清单" >&2
  echo "排查：确认 podman push 是否真的完成、Harbor 是否已回收该 tag" >&2
  exit 1
fi

echo "镜像存在性校验通过：$ref"
