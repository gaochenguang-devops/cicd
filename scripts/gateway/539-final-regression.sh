#!/bin/bash
set -uo pipefail
sleep 30
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
kubectl get pods -n podinfo --no-headers | awk '{print "  podinfo:", $1, $3}'
kubectl get pods -n webapp --no-headers | awk '{print "  webapp:", $1, $3}'
echo "=== 站点回归（13 域名） ==="
for h in gitlab keycloak harbor sonar artifactory jenkins argocd ldapadmin podinfo webapp prometheus alertmanager grafana; do
  code=$(curl -s -k -o /dev/null -w '%{http_code}' "https://$h.corp.local/" -m 8)
  printf "  %-12s %s\n" "$h" "$code"
done
echo "=== Harbor 首页 + ArgoCD 首页 ==="
curl -s -k -o /dev/null -w '  harbor / -> %{http_code}\n' https://harbor.corp.local/ -m 10
curl -s -k -o /dev/null -w '  argocd / -> %{http_code}\n' https://argocd.corp.local/ -m 10
