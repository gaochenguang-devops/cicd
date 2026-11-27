#!/bin/bash
set -u
LDAPSEARCH=$(command -v ldapsearch || echo "")
if [ -z "$LDAPSEARCH" ]; then
  LDAPSEARCH="podman exec openldap ldapsearch"
fi
echo "== people =="
$LDAPSEARCH -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=people,dc=corp,dc=local -LLL "(objectClass=inetOrgPerson)" uid mail uidNumber 2>/dev/null | sed -n 's/^uid: //p'
echo "count:"
$LDAPSEARCH -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=people,dc=corp,dc=local -LLL "(objectClass=inetOrgPerson)" dn 2>/dev/null | grep -c '^dn:'
echo "== groups =="
$LDAPSEARCH -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=groups,dc=corp,dc=local -LLL "(objectClass=groupOfNames)" cn member 2>/dev/null
echo "== base entries =="
$LDAPSEARCH -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b dc=corp,dc=local -LLL "(objectClass=organizationalUnit)" dn 2>/dev/null
