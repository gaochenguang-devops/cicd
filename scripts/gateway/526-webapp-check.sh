#!/bin/bash
set -uo pipefail
sleep 20
echo "=== webapp pods ==="
kubectl get pods -n webapp -o wide --no-headers
echo "=== webapp 最近事件 ==="
kubectl -n webapp get events --sort-by=.lastTimestamp | tail -8
echo "=== webapp app 状态 ==="
kubectl -n argocd get application webapp -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
echo "=== podinfo 探活（网关） ==="
curl -s -k -o /dev/null -w "  https://podinfo.corp.local -> %{http_code}\n" https://podinfo.corp.local/ -m 10
curl -s -k -o /dev/null -w "  https://webapp.corp.local -> %{http_code}\n" https://webapp.corp.local/ -m 10
