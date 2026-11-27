#!/usr/bin/env bash
set -uo pipefail
echo "===== 应用状态 ====="
kubectl -n argocd get applications podinfo webapp \
  -o custom-columns='NAME:.metadata.name,REV:.spec.source.targetRevision,DEPLOYED:.status.sync.revision,SYNC:.status.sync.status,HEALTH:.status.health.status' | sed 's/^/  /'
echo "===== podinfo 工作负载 ====="
kubectl -n podinfo get pods --no-headers -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' | sed 's/^/  /'
echo "===== 端口自检 ====="
echo "  root=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30095/)  version=$(curl -s http://127.0.0.1:30095/version | head -c 80)"
echo "  webapp=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30096/)"
echo "===== HPA 现状 ====="
kubectl -n podinfo get hpa --no-headers | sed 's/^/  /'
