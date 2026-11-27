#!/bin/bash
set -uo pipefail
POD=$(kubectl -n gateway get pods -o jsonpath='{.items[0].metadata.name}')
echo "=== 从 Pod 探 /metrics（宿主到 ClusterIP 不可达，Pod 内才准） ==="
kubectl -n gateway exec "$POD" -- sh -c '
for t in "harbor-core.harbor.svc.cluster.local:80/metrics" \
         "argocd-metrics.argocd.svc.cluster.local:8082/metrics" \
         "argocd-server-metrics.argocd.svc.cluster.local:8083/metrics" \
         "argocd-notifications-controller-metrics.argocd.svc.cluster.local:9001/metrics"; do
  code=$(curl -s -o /dev/null -m 6 -w "%{http_code}" "http://$t"); echo "  $t -> $code"
done'
echo "=== kube-state-metrics 镜像备选源 ==="
for img in docker.m.daocloud.io/kube-state-metrics/kube-state-metrics:v2.14.0 \
           docker.m.daocloud.io/bitnami/kube-state-metrics:2.14.0 \
           quay.io/prometheuscommunity/kube-state-metrics:v2.14.0 \
           registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0; do
  if timeout 120 podman pull -q "$img" >/dev/null 2>&1; then echo "  OK: $img"; else echo "  FAIL: $img"; fi
done
