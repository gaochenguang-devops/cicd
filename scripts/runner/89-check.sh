#!/usr/bin/env bash
set -uo pipefail
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null
for i in $(seq 1 12); do
  S=$(kubectl -n argocd get app podinfo -o jsonpath='{.status.sync.status}/{.status.health.status}')
  echo "  [$i] $S"
  case "$S" in *"/Healthy") break;; esac
  sleep 10
done
echo
kubectl -n podinfo get pods -o wide
echo
echo "== 服务自检 =="
curl -s -m 5 -o /dev/null -w "  /        http=%{http_code}\n" http://192.168.200.12:30095/
curl -s -m 5 http://192.168.200.12:30095/ | head -5
curl -s -m 5 -o /dev/null -w "  /healthz http=%{http_code}\n" http://192.168.200.12:30095/healthz
curl -s -m 5 -o /dev/null -w "  /readyz  http=%{http_code}\n" http://192.168.200.12:30095/readyz
curl -s -m 5 http://192.168.200.12:30095/version
echo
echo "== 镜像版本（滚动更新验证）=="
for p in $(kubectl -n podinfo get pods -l app=podinfo -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n podinfo get pod $p -o jsonpath="{.metadata.name}  {.spec.containers[0].image}  ready={.status.containerStatuses[0].ready}{\"\n\"}"
done
echo
echo "== ArgoCD 概况 =="
kubectl -n argocd get app podinfo -o jsonpath='{.status.sync.status} {.status.health.status} rev={.status.sync.revision}{"\n"}'
