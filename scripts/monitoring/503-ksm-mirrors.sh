#!/bin/bash
set -uo pipefail
IMGS=(
"docker.1ms.run/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0"
"dockerhub.icu/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0"
"docker.1panel.live/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0"
"hub.rat.dev/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0"
"docker.m.daocloud.io/bitnamilegacy/kube-state-metrics:2.14.0"
"docker.m.daocloud.io/prometheus/kube-state-metrics:v2.14.0"
)
for img in "${IMGS[@]}"; do
  if timeout 60 podman pull -q "$img" >/dev/null 2>&1; then echo "  OK: $img"; else echo "  FAIL: $img"; fi
done
podman images | grep -i kube-state || echo "  本地无 ksm 镜像"
