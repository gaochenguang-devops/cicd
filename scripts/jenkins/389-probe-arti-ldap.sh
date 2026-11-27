#!/bin/bash
set -uo pipefail
A='http://192.168.200.12:30092/artifactory'
echo "=== LDAP 里的普通账号 ==="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' \
  -b 'ou=people,dc=corp,dc=local' '(objectClass=inetOrgPerson)' uid 2>/dev/null | grep -E '^uid:' | head -15

echo "=== 用非 admin 的 LDAP 账号试上传 ==="
for U in devuser developer zhangsan lisi wangwu; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$U:__LDAP_USER_INIT_PASS__" -T /tmp/ldap.txt "$A/build-artifacts/maven-demo/_probe/ldap.txt" 2>/dev/null)
  [ "$code" != "000" ] && echo "  $U -> $code"
done
