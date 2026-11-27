#!/bin/bash
set -uo pipefail
echo "=== $(date +%T) keycloak 部署 env ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep KC_HOST
echo "=== pods ==="
kubectl -n keycloak get pods
echo "=== 主机 curl 探 discovery ==="
timeout 10 curl -sk https://keycloak.corp.local/realms/corp/.well-known/openid-configuration | head -c 200; echo
echo "=== 宿主是否有卡住的 curl/kcadm ==="
ps -eo pid,etimes,cmd | grep -E 'kcadm|curl' | grep -v grep | head -5
