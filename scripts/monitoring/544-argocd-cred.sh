#!/bin/bash
set -uo pipefail
curl -s -o /dev/null -w '  gateway  /api/v1/session -> %{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"__ARGOCD_ADMIN_PASS__"}' \
  https://argocd.corp.local/api/v1/session --resolve argocd.corp.local:443:192.168.200.210 -k
curl -s -o /dev/null -w '  clusterIP /api/v1/session -> %{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"__ARGOCD_ADMIN_PASS__"}' \
  http://10.101.14.25/api/v1/session

