#!/bin/bash
set -uo pipefail
for a in podinfo webapp; do
  kubectl -n argocd annotate application $a argocd.argoproj.io/refresh=normal --overwrite >/dev/null
done
for i in $(seq 1 12); do
  sleep 10
  R=$(kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.revision}')
  S=$(kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.status}')
  H=$(kubectl -n argocd get application podinfo -o jsonpath='{.status.health.status}')
  echo "[$((i*10))s] podinfo rev=$R sync=$S health=$H"
  [ "$R" = "6190a6cb" ] || [ "${#R}" = "40" -a "$R" != "ceacd286a38538772c8420ef9fcf75861aea29ff" ] && break
done
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
echo "=== pods ==="
kubectl get pods -n podinfo -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:..image --no-headers
kubectl get pods -n webapp -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:..image --no-headers
