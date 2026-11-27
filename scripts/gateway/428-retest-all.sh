#!/bin/bash
set -uo pipefail
VIP=192.168.200.210
for h in gitlab ldapadmin jenkins harbor sonar artifactory argocd keycloak podinfo webapp; do
  code=$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' --resolve $h.corp.local:443:$VIP https://$h.corp.local/)
  printf "  %-12s %s\n" "$h" "$code"
done
