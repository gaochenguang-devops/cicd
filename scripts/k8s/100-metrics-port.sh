#!/usr/bin/env bash
set -uo pipefail
kubectl -n kube-system patch deployment metrics-server --type=json -p '[
 {"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--kubelet-preferred-address-types=InternalIP","--kubelet-insecure-tls","--metric-resolution=15s","--cert-dir=/tmp","--secure-port=10250"]}
]' 2>&1 | tail -1
kubectl -n kube-system delete pod -l k8s-app=metrics-server --field-selector=status.phase=Running >/dev/null 2>&1 || true
sleep 30
kubectl -n kube-system get pod -l k8s-app=metrics-server
kubectl -n kube-system get endpoints metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io | tail -1
echo "== top =="
kubectl top nodes 2>&1 | head -3
kubectl top pods -n podinfo 2>&1 | head -4
echo "== HPA =="
kubectl -n podinfo get hpa
