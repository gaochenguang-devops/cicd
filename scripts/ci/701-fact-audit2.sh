#!/bin/bash
set -uo pipefail
H='-k --resolve harbor.corp.local:443:192.168.200.210'
GL='-k --resolve gitlab.corp.local:443:192.168.200.210'
TOK='__GITLAB_PAT__'

echo "=== Harbor robots（分页写法） ==="
curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' 'https://harbor.corp.local/api/v2.0/robots?page=1&page_size=50' | head -c 600; echo
echo "=== Harbor 仓库清单（按项目） ==="
for p in apps library; do
  echo -n "  $p: "
  curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' "https://harbor.corp.local/api/v2.0/projects/$p/repositories?page_size=50" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print([r["name"] for r in d] if isinstance(d,list) else d)'
done

echo "=== GitLab 各项目分支/变量 ==="
for pid in $(curl -s $GL --header "PRIVATE-TOKEN: $TOK" 'https://gitlab.corp.local/api/v4/projects?per_page=100' | python3 -c 'import sys,json;[print(p["id"]) for p in json.load(sys.stdin)]'); do
  NAME=$(curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$pid" | python3 -c 'import sys,json;print(json.load(sys.stdin)["path_with_namespace"])')
  BR=$(curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$pid/repository/branches" | python3 -c 'import sys,json;print([b["name"] for b in json.load(sys.stdin)])')
  VR=$(curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$pid/variables" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d), [v["key"] for v in d] if isinstance(d,list) else d)')
  echo "  $NAME | branches=$BR | vars=$VR"
done

echo "=== podinfo 最近 5 条流水线 ==="
PID=$(curl -s $GL --header "PRIVATE-TOKEN: $TOK" 'https://gitlab.corp.local/api/v4/projects?per_page=100' | python3 -c 'import sys,json;[print(p["id"]) for p in json.load(sys.stdin) if p["path"]=="podinfo"]')
curl -s $GL --header "PRIVATE-TOKEN: $TOK" "https://gitlab.corp.local/api/v4/projects/$PID/pipelines?per_page=6" | python3 -c '
import sys,json
for p in json.load(sys.stdin): print("  #%s %-9s %-6s %s" % (p["id"],p["status"],p["ref"],p["created_at"][:16]))'

echo "=== LDAP 条目明细 ==="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=people,dc=corp,dc=local' uid 2>/dev/null | grep '^uid:' | sed 's/^/  /'
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=groups,dc=corp,dc=local' cn 2>/dev/null | grep '^cn:' | sed 's/^/  group: /'

echo "=== Jenkins 凭据（JCasC 与 credentials.xml） ==="
JPOD=$(kubectl -n jenkins get pods -o name | head -1)
kubectl -n jenkins exec $JPOD -- sh -c 'grep -o "<id>[^<]*</id>" /var/jenkins_home/credentials.xml 2>/dev/null' | sed 's/^/  /'
kubectl -n jenkins get secret jenkins-casc-secrets -o jsonpath='{range .data}{@}{"\n"}{end}' 2>/dev/null | head -3 | cut -c1-40 | sed 's/^/  casc-secret-key-len: /'

