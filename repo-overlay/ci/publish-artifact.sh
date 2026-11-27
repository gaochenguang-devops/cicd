#!/usr/bin/env bash
# 制品发布：从构建产物镜像中提取二进制 → 打包 → 上传 Artifactory → 读回校验
set -euo pipefail

IMG="${IMAGE_NAME}:${TAG}"
PKG="podinfo-${TAG}.tar.gz"
URL="${ARTIFACTORY_URL}/artifactory/${ARTIFACT_REPO}/podinfo/${CI_COMMIT_REF_NAME}/${TAG}"
CTR="arti-tmp-$$"
AUTH=(-u "${ARTIFACTORY_USER}:${ARTIFACTORY_PASS}")

cleanup () { podman rm -f "$CTR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 从镜像 $IMG 提取二进制 =="
podman create --name "$CTR" "$IMG" >/dev/null
podman cp "$CTR:/home/app/podinfo" ./podinfo
podman cp "$CTR:/usr/local/bin/podcli" ./podcli

echo "== 打包 + 生成校验值（纯 hash，便于机器比对）=="
tar czf "$PKG" podinfo podcli
sha256sum "$PKG" | awk '{print $1}' > "${PKG}.sha256"
LOCAL_SHA=$(cat "${PKG}.sha256")
ls -lh "$PKG" "${PKG}.sha256"
echo "  本地 sha256=$LOCAL_SHA"

echo "== 上传 Artifactory：$URL =="
curl -fsS "${AUTH[@]}" -T "$PKG" "${URL}/${PKG}" >/dev/null
curl -fsS "${AUTH[@]}" -T "${PKG}.sha256" "${URL}/${PKG}.sha256" >/dev/null
echo "  上传完成"

echo "== 读回校验（以仓库里的字节为准）=="
curl -fsS "${AUTH[@]}" "${URL}/${PKG}.sha256" -o /tmp/remote.sha256
REMOTE_SHA=$(tr -d '\r\n' < /tmp/remote.sha256)
curl -fsS "${AUTH[@]}" "${URL}/${PKG}" -o "/tmp/${PKG}"
READBACK_SHA=$(sha256sum "/tmp/${PKG}" | awk '{print $1}')

echo "  仓库 sha256=$REMOTE_SHA"
echo "  读回  sha256=$READBACK_SHA"
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ] || [ "$LOCAL_SHA" != "$READBACK_SHA" ]; then
  echo "!! 制品校验失败（本地/元数据/读回不一致）" >&2
  exit 1
fi
echo "制品已发布并校验通过：${URL}/${PKG}"
