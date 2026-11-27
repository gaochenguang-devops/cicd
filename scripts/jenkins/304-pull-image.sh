#!/usr/bin/env bash
# Jenkins 官方镜像：docker.io/jenkins/jenkins:lts-jdk21（注意不是 library/jenkins）
# 拉取后转存到本地 Harbor 的 library 项目（public），K8s 从内网仓库拉取
set -uo pipefail
SRC="docker.io/jenkins/jenkins:lts-jdk21"
DST="192.168.200.12:30090/library/jenkins:lts-jdk21"

podman image exists "$SRC" || podman pull "$SRC" || exit 1
podman tag "$SRC" "$DST"
podman login -u admin -p '__HARBOR_ADMIN_PASS__' 192.168.200.12:30090 || exit 1
podman push "$DST" || exit 1

echo "== registry 校验 =="
curl -s -o /dev/null -w 'manifests HTTP %{http_code}\n' \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json' \
  "http://192.168.200.12:30090/v2/library/jenkins/manifests/lts-jdk21"
podman images | grep jenkins
