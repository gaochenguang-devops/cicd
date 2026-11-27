#!/usr/bin/env bash
set -uo pipefail
echo "--- 连跑两次（幂等）---"
for i in 1 2; do /usr/local/bin/ldap-gitlab-sync.sh 2>&1 | grep -E "结束|!!"; done
echo "--- GitLab 里 LDAP 身份账号 ---"
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/users?per_page=100' \
  | jq -r '[.[]|select((.identities|length)>0)|.username]|join(", ")'
echo "--- LDAP people 条目数 ---"
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '__LDAP_ADMIN_PASS__' \
  -b ou=people,dc=corp,dc=local -LLL dn | grep -c '^dn'
echo "--- 三组成员 ---"
for g in devops:5 developers:6 qa:7; do
  cn=${g%%:*}; id=${g##*:}
  echo "  $cn: $(curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' "http://192.168.200.12/api/v4/groups/$id/members/all" | jq -r '[.[]|.username]|join(", ")')"
done
