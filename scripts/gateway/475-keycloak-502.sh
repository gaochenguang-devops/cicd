#!/bin/bash
set -uo pipefail
echo "=== keycloak svc / endpoints ==="
kubectl -n keycloak get svc keycloak -o wide
kubectl -n keycloak get endpoints keycloak
echo "=== 直接打 keycloak ClusterIP ==="
CIP=$(kubectl -n keycloak get svc keycloak -o jsonpath='{.spec.clusterIP}')
NP=$(kubectl -n podinfo get pod -o name | head -1)
kubectl -n podinfo exec $NP -- sh -c "curl -s -o /dev/null -w '  keycloak svc -> %{http_code}\n' -H 'Host: keycloak.corp.local' http://$CIP/realms/corp/.well-known/openid-configuration -m 8" 2>&1 | tail -2
echo "=== 网关 error.log 尾部 ==="
kubectl -n gateway exec deploy/gateway -- sh -c 'tail -6 /var/log/nginx/error.log 2>/dev/null || tail -6 /dev/stderr' 2>&1 | tail -8
echo "=== 网关里直连 keycloak ClusterIP ==="
kubectl -n gateway exec deploy/gateway -- sh -c "curl -s -o /dev/null -w '  gw->kc %{http_code}\n' -H 'Host: x' http://$CIP/realms/corp/.well-known/openid-configuration -m 8" 2>&1 | tail -2
