#!/bin/bash
set -u
echo "== all people dn/cn/uid =="
podman exec openldap ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
 -b ou=people,dc=corp,dc=local -LLL "(objectClass=inetOrgPerson)" dn cn uid uidNumber mail 2>/dev/null
echo "== memberOf of the two =="
for u in gaochenguang gaofei; do
  echo "-- $u"
  podman exec openldap ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
   -b ou=people,dc=corp,dc=local -LLL "(uid=$u)" memberOf 2>/dev/null
done
