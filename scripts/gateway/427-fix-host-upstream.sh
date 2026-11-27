#!/bin/bash
set -uo pipefail
echo "=== 现状复查 ==="
POD=$(kubectl -n gateway get pods -o jsonpath='{.items[0].metadata.name}')
kubectl -n gateway exec "$POD" -- sh -c 'curl -s -o /dev/null -m 5 -w "  svc_ldap=%{http_code}\n" http://ldapadmin-host.gateway.svc.cluster.local:8090/; curl -s -o /dev/null -m 5 -w "  svc_gitlab=%{http_code}\n" http://gitlab-host.gateway.svc.cluster.local:80/'

echo "=== 改为直连宿主 IP（绕过无 selector Service 的 DNAT 问题） ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' > /tmp/nginx.conf
python3 - <<'PY'
p='/tmp/nginx.conf'; s=open(p).read()
s=s.replace('upstream gitlab_host      { server gitlab-host.gateway.svc.cluster.local:80; }',
            'upstream gitlab_host      { server 192.168.200.12:80; }')
s=s.replace('upstream ldapadmin_host   { server ldapadmin-host.gateway.svc.cluster.local:8090; }',
            'upstream ldapadmin_host   { server 192.168.200.12:8090; }')
open(p,'w').write(s)
PY
grep -n 'upstream gitlab_host\|upstream ldapadmin_host' /tmp/nginx.conf
kubectl -n gateway create configmap gateway-nginx-conf --from-file=nginx.conf=/tmp/nginx.conf \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=120s

echo "=== 复测 ==="
for h in gitlab ldapadmin; do
  curl -s -k -o /dev/null -m 10 -w "  $h=%{http_code}\n" --resolve $h.corp.local:443:192.168.200.210 https://$h.corp.local/
done
