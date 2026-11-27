#!/usr/bin/env bash
set -uo pipefail
kubectl -n kube-system patch deployment metrics-server --type=json -p '[
 {"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--kubelet-preferred-address-types=InternalIP","--kubelet-insecure-tls","--metric-resolution=15s","--cert-dir=/tmp"]},
 {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"tmp","emptyDir":{}}]},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"tmp","mountPath":"/tmp"}]}
]' 2>&1 | tail -1
sleep 30
kubectl -n kube-system get pod -l k8s-app=metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io 2>/dev/null | tail -2
echo "== kubectl top =="
kubectl top nodes 2>&1 | head -3
kubectl top pods -n podinfo 2>&1 | head -5
echo
kubectl -n podinfo get hpa
