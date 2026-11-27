#!/bin/bash
set -uo pipefail
echo "=== GitLab：external_url 来源 ==="
kubectl -n gitlab get cm --no-headers 2>/dev/null | awk '{print "  cm:",$1}'
kubectl -n gitlab get deploy -o name 2>/dev/null | while read d; do
  echo "  deploy: $d"; kubectl -n gitlab get $d -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | grep -iE 'EXTERNAL|GITLAB_OMNIBUS' | sed 's/^/    /' | head -6
done
echo "=== 实测：gitlab 网关返回的 Location ==="
curl -sk --resolve gitlab.corp.local:443:192.168.200.210 -o /dev/null -D - https://gitlab.corp.local/users/sign_in | grep -i '^location' | head -2
echo "=== Sonar 返回的 Location（OIDC 用） ==="
curl -sk --resolve sonar.corp.local:443:192.168.200.210 -o /dev/null -D - https://sonar.corp.local/sessions/init/gitlab 2>/dev/null | head -5
echo "=== 各域名一次总扫（状态码） ==="
for h in gitlab jenkins harbor sonar artifactory argocd keycloak ldapadmin podinfo webapp prometheus alertmanager grafana; do
  code=$(curl -sk --resolve $h.corp.local:443:192.168.200.210 -o /dev/null -w '%{http_code}' https://$h.corp.local/)
  printf '  %-12s %s\n' $h $code
done

