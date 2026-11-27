#!/usr/bin/env bash
set -uo pipefail
BASE="dc=corp,dc=local"
TOK=__GITLAB_PAT__
echo "--- people 用户数（不含 ou 本身）---"
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=people,dc=corp,dc=local -LLL "(objectClass=posixAccount)" uid | grep -c '^uid: '
echo "--- GitLab LDAP 账号 ---"
curl -s -H "PRIVATE-TOKEN: $TOK" 'http://192.168.200.12/api/v4/users?per_page=100' \
  | jq -r '[.[]|select((.identities|length)>0)|.username]|join(", ")'
echo "--- 同步一次（应全零）---"
/usr/local/bin/ldap-gitlab-sync.sh 2>&1 | grep -E "结束|!!"
echo "--- 定时器 ---"
systemctl is-enabled ldap-gitlab-sync.timer; systemctl list-timers ldap-gitlab-sync.timer --no-pager | sed -n '2p'
echo "--- 组 ---"
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=groups,dc=corp,dc=local -LLL "(objectClass=groupOfNames)" cn | grep '^cn:' | tr '\n' ' '; echo
echo "--- 残留测试账号 ---"
for u in ui01 ui02 ui03 md5t tmp03; do
  n=$(curl -s -H "PRIVATE-TOKEN: $TOK" "http://192.168.200.12/api/v4/users?username=$u" | jq 'length')
  l=$(ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' -b ou=people,dc=corp,dc=local -LLL "(uid=$u)" dn 2>/dev/null | grep -c '^dn' || true)
  echo "  $u: gitlab=$n ldap=$l"
done
