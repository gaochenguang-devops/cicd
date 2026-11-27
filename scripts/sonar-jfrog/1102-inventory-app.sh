#!/usr/bin/env bash
set -uo pipefail
echo "===== Keycloak clients (realm corp) ====="
TOK=$(curl -s -X POST 'http://127.0.0.1:30087/realms/master/protocol/openid-connect/token' \
  -d 'client_id=admin-cli' -d 'username=admin' -d 'password=__KEYCLOAK_ADMIN_PASS__' -d 'grant_type=password' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOK" 'http://127.0.0.1:30087/admin/realms/corp/clients?max=100' \
 | python3 -c 'import sys,json
for c in json.load(sys.stdin): print(" ", c["clientId"], "protocol=", c.get("protocol"), "redirects=", (c.get("redirectUris") or [])[:1])'
echo
echo "===== Keycloak 用户数 / 组 ====="
curl -s -H "Authorization: Bearer $TOK" 'http://127.0.0.1:30087/admin/realms/corp/users?max=100' | python3 -c 'import sys,json;print("users=", len(json.load(sys.stdin)))'
curl -s -H "Authorization: Bearer $TOK" 'http://127.0.0.1:30087/admin/realms/corp/groups?max=100' | python3 -c 'import sys,json;print("groups=", [g["name"] for g in json.load(sys.stdin)])'
echo
echo "===== Harbor 项目 / robot ====="
curl -s -u admin:'__HARBOR_ADMIN_PASS__' 'http://127.0.0.1:30090/api/v2.0/projects?page_size=50' \
 | python3 -c 'import sys,json
for p in json.load(sys.stdin): print("  project:", p["name"], "repos=", p.get("repo_count"))'
curl -s -u admin:'__HARBOR_ADMIN_PASS__' 'http://127.0.0.1:30090/api/v2.0/robots?page_size=50' \
 | python3 -c 'import sys,json
for r in json.load(sys.stdin): print("  robot:", r["name"], r.get("level"))'
echo
echo "===== GitLab 项目 ====="
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/projects?per_page=50&simple=true' \
 | python3 -c 'import sys,json
for p in json.load(sys.stdin): print("  ", p["path_with_namespace"], "default=", p["default_branch"], "last=", (p.get("last_activity_at") or "")[:10])'
echo
echo "===== GitLab 用户数 / 组 ====="
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/users?per_page=100' | python3 -c 'import sys,json;d=json.load(sys.stdin);print("users=",len(d))'
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/groups?per_page=50' | python3 -c 'import sys,json;print("groups=",[g["full_path"] for g in json.load(sys.stdin)])'
echo
echo "===== Sonar 项目 / 质量门 ====="
curl -s -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" 'http://127.0.0.1:30091/api/projects/search' | python3 -c 'import sys,json;print([ (c["key"],c["name"]) for c in json.load(sys.stdin)["components"]])'
curl -s -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" 'http://127.0.0.1:30091/api/qualitygates/list' | python3 -c 'import sys,json;print([(q["name"],q["isDefault"]) for q in json.load(sys.stdin)["qualitygates"]])'
echo
echo "===== LDAP 账号/组 ====="
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=people,dc=corp,dc=local' uid 2>/dev/null | grep -c '^uid' || true
ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '__LDAP_ADMIN_PASS__' -b 'ou=groups,dc=corp,dc=local' cn 2>/dev/null | grep '^cn:' || true
