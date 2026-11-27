#!/usr/bin/env bash
set -uo pipefail
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null
sleep 40
echo "== 应用状态 =="
kubectl -n argocd get app podinfo -o jsonpath='HEALTH={.status.health.status} SYNC={.status.sync.status} MSG=[{.status.health.message}] REV={.status.sync.revision}{"\n"}'
echo
echo "== 资源逐项 =="
kubectl -n argocd get app podinfo -o json | jq -r '.status.resources[] | "  \(.kind)/\(.name) sync=\(.status // "-") health=\(.health.status // "-") \(.health.message // "")"'
echo
echo "== controller 最近关于 podinfo 的日志 =="
kubectl -n argocd logs deploy/argocd-application-controller --tail=200 2>/dev/null | grep -i "podinfo" | tail -6
