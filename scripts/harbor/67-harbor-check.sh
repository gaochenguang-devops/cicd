#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== PV =="
kubectl get pv -o wide
echo
echo "== PV 详情（registry）=="
kubectl get pv harbor-registry-pv -o yaml | sed -n '1,40p'
echo
echo "== PVC 详情 =="
kubectl -n harbor get pvc harbor-registry-pvc -o yaml | sed -n '/spec:/,/status:/p'
echo
echo "== Pod =="
kubectl -n harbor get pods -o wide
echo
echo "== events =="
kubectl -n harbor get events --sort-by=.lastTimestamp | tail -8
