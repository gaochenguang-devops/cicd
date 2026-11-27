#!/bin/bash
set -uo pipefail
POD=$(kubectl -n gateway get pods -o jsonpath='{.items[0].metadata.name}')
echo "=== Pod 直连宿主 8090（HTTP 级） ==="
kubectl -n gateway exec "$POD" -- sh -c 'curl -s -o /dev/null -m 5 -w "  direct=%{http_code}\n" http://192.168.200.12:8090/ ; curl -s -m 5 http://192.168.200.12:8090/ | head -c 200; echo'
echo "=== Pod 走 Service（Endpoint 版） ==="
kubectl -n gateway exec "$POD" -- sh -c 'curl -s -o /dev/null -m 5 -w "  via_svc=%{http_code}\n" http://ldapadmin-host.gateway.svc.cluster.local:8090/'
echo "=== Endpoints 现状 ==="
kubectl -n gateway get endpoints ldapadmin-host -o yaml | sed -n '1,20p'
echo "=== 网关侧再测（新 Pod） ==="
kubectl -n gateway logs deploy/gateway --tail=3 | tail -3
