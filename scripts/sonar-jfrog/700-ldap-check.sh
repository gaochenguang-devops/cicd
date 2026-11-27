#!/bin/bash
echo "=== 全树 groupOfNames ==="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'dc=corp,dc=local' '(objectClass=groupOfNames)' dn cn 2>/dev/null | grep -E '^(dn|cn):' | sed 's/^/  /'
echo "=== 非标准 DN（cn= 开头的人） ==="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=people,dc=corp,dc=local' '(objectClass=inetOrgPerson)' dn 2>/dev/null | grep '^dn:' | sed 's/^/  /'

