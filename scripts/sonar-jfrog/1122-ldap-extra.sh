#!/bin/bash
set -u
echo "== extra DNs under base =="
podman exec openldap ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
 -b dc=corp,dc=local -LLL "(cn=test)" dn objectClass member 2>/dev/null
echo "== gitlab ldap_enabled =="
grep -E "ldap_enabled|openid_connect" /etc/gitlab/gitlab.rb | grep -v '^\s*#' | head -20
echo "== harbor auth_mode =="
curl -s -u admin:'__HARBOR_ADMIN_PASS__' "http://127.0.0.1:30090/api/v2.0/configurations" | python3 -c "import sys,json;d=json.load(sys.stdin);print({k:d[k] for k in ['auth_mode','oidc_name','oidc_groups_claim'] if k in d})" 2>/dev/null || echo "harbor api failed"
echo "== keycloak users count =="
KC=$(kubectl -n keycloak get pods -o name | head -1)
kubectl -n keycloak exec $KC -- /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password '__KEYCLOAK_ADMIN_PASS__' >/dev/null 2>&1
kubectl -n keycloak exec $KC -- /opt/keycloak/bin/kcadm.sh get users -r corp --fields username 2>/dev/null | grep -c username
