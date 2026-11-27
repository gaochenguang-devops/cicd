#!/usr/bin/env bash
set -uo pipefail
kubectl patch clusterrole system:metrics-server --type=json -p '[
 {"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["nodes"],"verbs":["get","list","watch"]}}
]' 2>&1 | tail -1
kubectl -n kube-system delete pod -l k8s-app=metrics-server --field-selector=status.phase=Failed >/dev/null 2>&1 || true
kubectl -n kube-system rollout restart deploy/metrics-server >/dev/null
sleep 35
kubectl -n kube-system get pod -l k8s-app=metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io | tail -1
echo "== top =="
kubectl top nodes 2>&1 | head -3
kubectl top pods -n podinfo 2>&1 | head -4
echo "== HPA =="
kubectl -n podinfo get hpa
