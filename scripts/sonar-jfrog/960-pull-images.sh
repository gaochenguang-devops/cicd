#!/usr/bin/env bash
# 拉取 SonarQube 社区版与 JFrog Artifactory OSS，转存本地 Harbor library
set -uo pipefail
HARBOR=192.168.200.12:30090
podman login -u admin -p '__HARBOR_ADMIN_PASS__' "$HARBOR" >/dev/null || exit 1

mirror () {
  local src="$1" dst="$2"
  if podman image exists "$dst"; then echo "$dst 已存在，跳过"; return 0; fi
  echo "== pull $src"
  podman pull "$src" || return 1
  podman tag "$src" "$dst"
  podman push "$dst" || return 1
  echo "== pushed $dst"
}

mirror docker.io/library/sonarqube:10.7-community "$HARBOR/library/sonarqube:10.7-community"

for tag in 7.104.7 7.98.9 7.90.15 7.77.10; do
  if mirror "releases-docker.jfrog.io/jfrog/artifactory-oss:$tag" "$HARBOR/library/artifactory-oss:$tag"; then
    echo "ARTIFACTORY_TAG=$tag"; break
  fi
  echo "tag $tag 失败，换下一个"
done

echo "==== 本地镜像 ===="
podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -E 'sonarqube|artifactory'
echo "==== Harbor 校验 ===="
for r in library/sonarqube library/artifactory-oss; do
  curl -s -o /dev/null -w "$r -> %{http_code}\n" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json' \
    -u 'admin:__HARBOR_ADMIN_PASS__' "http://$HARBOR/v2/$r/tags/list"
done
