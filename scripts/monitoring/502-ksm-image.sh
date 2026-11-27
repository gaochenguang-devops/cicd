#!/bin/bash
set -uo pipefail
echo "=== 拉取失败原因 ==="
timeout 100 podman pull docker.m.daocloud.io/bitnami/kube-state-metrics:2.14.0 2>&1 | tail -5
echo "=== 试其他镜像源 ==="
for img in docker.io/bitnami/kube-state-metrics:2.14.0 \
           docker.m.daocloud.io/docker.io/bitnami/kube-state-metrics:2.14.0 \
           ghcr.io/prometheus-community/kube-state-metrics:v2.14.0 \
           docker.m.daocloud.io/ghcr.io/prometheus-community/kube-state-metrics:v2.14.0 ; do
  if timeout 150 podman pull -q "$img" >/dev/null 2>&1; then echo "  OK: $img"; else echo "  FAIL: $img"; fi
done
