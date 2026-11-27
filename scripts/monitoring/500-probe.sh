#!/bin/bash
set -uo pipefail
echo "=== 抓取目标可用性预检（集群内 /metrics） ==="
probe() { code=$(curl -s -o /dev/null -m 6 -w '%{http_code}' "$1"); echo "  $2 -> $code"; }
probe http://harbor-core.harbor.svc.cluster.local:80/metrics "harbor-core:80 /metrics"
probe http://argocd-metrics.argocd.svc.cluster.local:8082/metrics "argocd-metrics:8082"
probe http://argocd-server-metrics.argocd.svc.cluster.local:8083/metrics "argocd-server-metrics:8083"
probe http://argocd-notifications-controller-metrics.argocd.svc.cluster.local:9001/metrics "argocd-notif-metrics:9001"
probe http://192.168.200.12:30088/metrics "jenkins:30088 /metrics(无插件应为404)"
echo "=== 监听端口/服务核对 ==="
kubectl get svc -A | grep -E 'harbor-core|argocd-metrics|argocd-server-metrics|argocd-notifications' 
echo "=== 镜像源可达性 ==="
podman pull -q quay.io/prometheus/prometheus:v2.55.1 >/dev/null 2>&1 && echo "  prometheus ok" || echo "  prometheus FAIL"
podman pull -q quay.io/prometheus/alertmanager:v0.27.0 >/dev/null 2>&1 && echo "  alertmanager ok" || echo "  alertmanager FAIL"
podman pull -q quay.io/prometheus/node-exporter:v1.8.1 >/dev/null 2>&1 && echo "  node-exporter ok" || echo "  node-exporter FAIL"
podman pull -q docker.m.daocloud.io/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0 >/dev/null 2>&1 && echo "  ksm ok" || echo "  ksm FAIL"
