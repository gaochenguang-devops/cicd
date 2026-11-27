#!/bin/bash
set -uo pipefail
H='-k --resolve harbor.corp.local:443:192.168.200.210'
echo "=== Harbor robots ==="
curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' 'https://harbor.corp.local/api/v2.0/robots?page_size=100' | python3 -c '
import sys,json
d=json.load(sys.stdin)
for r in d: print("  ",r["name"],"| level:",r.get("level"),"| expires:",r.get("expires_at"))
print("  total:",len(d))'
echo "=== Harbor projects ==="
curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' 'https://harbor.corp.local/api/v2.0/projects?page_size=100' | python3 -c '
import sys,json;d=json.load(sys.stdin);print("  ",[(p["name"],p.get("public")) for p in d])'
echo "=== Harbor repositories 数量 ==="
curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' 'https://harbor.corp.local/api/v2.0/search?q=' | python3 -c '
import sys,json;d=json.load(sys.stdin);print("  repos:",len(d.get("repository",[])))'

echo "=== GitLab：项目与分支 ==="
GL='-k --resolve gitlab.corp.local:443:192.168.200.210'
TOK='__GITLAB_PAT__'
curl -s $GL --header "PRIVATE-TOKEN: $TOK" 'https://gitlab.corp.local/api/v4/projects?per_page=100' | python3 -c '
import sys,json
d=json.load(sys.stdin)
for p in d: print("  project:",p["path_with_namespace"])
'
POD=$(curl -s $GL --header "PRIVATE-TOKEN: $TOK" 'https://gitlab.corp.local/api/v4/projects?per_page=100' | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$POD/repository/branches" | python3 -c 'import sys,json;print("  branches:",[b["name"] for b in json.load(sys.stdin)])'
echo "=== GitLab CI 变量 ==="
curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$POD/variables" | python3 -c '
import sys,json;d=json.load(sys.stdin);print("  count:",len(d));print("  keys:",[v["key"] for v in d])'

echo "=== Jenkins 凭据 / 任务 ==="
JPOD=$(kubectl -n jenkins get pods -o name | head -1)
kubectl -n jenkins exec $JPOD -- sh -c 'ls /var/jenkins_home/credentials.xml >/dev/null 2>&1 && grep -c "<org.jenkinsci.plugins.plaincredentials" /var/jenkins_home/credentials.xml' 2>/dev/null | sed 's/^/  plain-creds: /'
kubectl -n jenkins exec $JPOD -- sh -c 'ls -d /var/jenkins_home/jobs/* 2>/dev/null | sed "s#/var/jenkins_home/jobs/#  job: #"' 2>/dev/null

echo "=== LDAP 用户/组 ==="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=people,dc=corp,dc=local' dn 2>/dev/null | grep -c '^dn:' | sed 's/^/  users: /'
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=groups,dc=corp,dc=local' dn 2>/dev/null | grep -c '^dn:' | sed 's/^/  groups: /'

echo "=== Sonar 项目 ==="
curl -s $H --resolve sonar.corp.local:443:192.168.200.210 -u '__SONAR_CI_TOKEN__:' 'https://sonar.corp.local/api/projects/search' 2>/dev/null | python3 -c '
import sys,json
try:
  d=json.load(sys.stdin); print("  projects:",[p["key"] for p in d["components"]])
except Exception as e: print("  (auth/parse fail)")'

echo "=== 最近流水线（GitLab） ==="
curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$POD/pipelines?per_page=5" | python3 -c '
import sys,json
for p in json.load(sys.stdin): print("  #%s %s %s" % (p["id"],p["status"],p["ref"]))'

