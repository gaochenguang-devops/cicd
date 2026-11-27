#!/usr/bin/env bash
set -uo pipefail
kubectl -n argocd annotate application webapp argocd.argoproj.io/refresh=hard --overwrite >/dev/null
sleep 45
echo "== ArgoCD 应用总览 =="
kubectl -n argocd get applications
echo
echo "== webapp 非健康资源 =="
kubectl -n argocd get app webapp -o json | jq -r '.status.resources[] | select(.health.status != null and .health.status != "Healthy") | "  \(.kind)/\(.name) \(.health.status) \(.health.message // "")"'
echo
echo "== 前端调用后端（POST /echo）=="
curl -s -m 8 -X POST -d '{"msg":"hello from ci-cd"}' -H 'Content-Type: application/json' \
  http://192.168.200.12:30096/echo -o /tmp/e.json -w "  http=%{http_code}\n"
cat /tmp/e.json 2>/dev/null | head -c 400; echo
echo
echo "== HPA 现状 =="
kubectl -n webapp get hpa
kubectl -n podinfo get hpa
echo
echo "== 全部命名空间 Pod 概况 =="
kubectl get pods -A --field-selector=status.phase=Running 2>/dev/null | awk 'NR==1{print} $1!~/kube-system/{print}' | head -25
echo
echo "== 节点资源 =="
kubectl top node 2>/dev/null | head -2
free -m | head -2
