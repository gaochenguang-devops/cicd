#!/bin/bash
set -uo pipefail
HARBOR=192.168.200.12:30090
CRED='admin:__HARBOR_ADMIN_PASS__'
push() {
  local src="$1" name="$2" tag="$3"
  if podman images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$HARBOR/library/$name:$tag"; then
    echo "  已存在: $name:$tag"; return 0
  fi
  if ! podman image exists "$src"; then
    echo "  拉取 $src"; podman pull -q "$src" >/dev/null 2>&1 || { echo "  !! 拉失败 $src"; return 1; }
  fi
  podman tag "$src" "$HARBOR/library/$name:$tag"
  podman push -q --creds "$CRED" --tls-verify=false "$HARBOR/library/$name:$tag" >/dev/null 2>&1 \
    && echo "  OK: $name:$tag" || echo "  !! push 失败 $name:$tag"
}

push quay.io/prometheus/prometheus:v2.55.1              prometheus v2.55.1
push quay.io/prometheus/alertmanager:v0.27.0            alertmanager v0.27.0
push quay.io/prometheus/node-exporter:v1.8.1            node-exporter v1.8.1
push docker.m.daocloud.io/bitnamilegacy/kube-state-metrics:2.14.0 kube-state-metrics 2.14.0
echo "=== python:3.11-alpine（企业微信桥接用） ==="
podman pull -q docker.m.daocloud.io/library/python:3.11-alpine >/dev/null 2>&1 \
  && { podman tag docker.m.daocloud.io/library/python:3.11-alpine $HARBOR/library/python:3.11-alpine; \
       podman push -q --creds "$CRED" --tls-verify=false $HARBOR/library/python:3.11-alpine >/dev/null 2>&1 \
       && echo "  OK: python:3.11-alpine" || echo "  !! push 失败 python"; } || echo "  !! 拉不到 python:3.11-alpine"

echo "=== 结果 ==="
podman images --format '{{.Repository}}:{{.Tag}}' | grep '192.168.200.12:30090/library' | sort
