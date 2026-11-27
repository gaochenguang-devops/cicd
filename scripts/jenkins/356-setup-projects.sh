#!/bin/bash
set -uo pipefail
H='http://192.168.200.12:30090'
AH='admin:__HARBOR_ADMIN_PASS__'
GL='http://192.168.200.12/api/v4'
TOK='__GITLAB_PAT__'

echo "=== 1) robot: 加 library 的 pull 权限（Jib 要拉基础镜像） ==="
RID=$(curl -s -u "$AH" "$H/api/v2.0/robots?page_size=100" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(next((r["id"] for r in d if r["name"]=="robot$apps+jenkins-ci"),""))')
echo "existing robot id: ${RID:-none}"
[ -n "$RID" ] && curl -s -o /dev/null -w 'delete=%{http_code}\n' -u "$AH" -X DELETE "$H/api/v2.0/robots/$RID"
curl -s -u "$AH" -H 'Content-Type: application/json' -X POST "$H/api/v2.0/robots" -d '{
 "name":"jenkins-ci","description":"Jenkins pipeline push/pull","level":"project","duration":-1,
 "permissions":[
   {"kind":"project","namespace":"apps","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]},
   {"kind":"project","namespace":"library","access":[{"resource":"repository","action":"pull"}]}
 ]}' | python3 -c 'import sys,json;d=json.load(sys.stdin);print("robot:",d.get("name"));print("secret:",d.get("secret"));print("errors:",d.get("errors"))'

echo "=== 2) GitLab projects ==="
for p in jenkins-shared-library demo-maven; do
  code=$(curl -s -o /tmp/p.json -w '%{http_code}' -H "PRIVATE-TOKEN: $TOK" -X POST "$GL/projects" -d "name=$p&visibility=private&initialize_with_readme=false")
  echo "$p -> $code $(head -c 120 /tmp/p.json)"
done
curl -s -H "PRIVATE-TOKEN: $TOK" "$GL/projects?per_page=50&simple=true" | python3 -c 'import sys,json;[print(" ",p["id"],p["path_with_namespace"]) for p in json.load(sys.stdin)]'

echo "=== 3) 目录 ==="
mkdir -p /root/jenkins-src/demo-maven/src/main/java/com/corp/demo
mkdir -p /root/jenkins-src/demo-maven/src/test/java/com/corp/demo
mkdir -p /root/jenkins-src/shared-library/vars
mkdir -p /root/jenkins-src/shared-library/src/com/corp/platform
echo ok
