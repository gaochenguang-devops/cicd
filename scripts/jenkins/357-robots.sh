#!/bin/bash
set -uo pipefail
H='http://192.168.200.12:30090'
AH='admin:__HARBOR_ADMIN_PASS__'

mk() {
  local name=$1 ns=$2 access=$3
  local existing
  existing=$(curl -s -u "$AH" "$H/api/v2.0/robots?page_size=100" | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((r['id'] for r in d if r['name']=='robot\$$ns+$name'),''))")
  if [ -n "$existing" ]; then
    echo "$name already exists (id=$existing)"
    return
  fi
  curl -s -u "$AH" -H 'Content-Type: application/json' -X POST "$H/api/v2.0/robots" -d "{
   \"name\":\"$name\",\"duration\":-1,\"level\":\"project\",
   \"permissions\":[{\"kind\":\"project\",\"namespace\":\"$ns\",\"access\":$access}]}" \
   | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  robot:",d.get("name"),"secret:",d.get("secret"),"errors:",d.get("errors"))'
}

echo "=== apps 项目：拉+推 ==="
mk "jenkins-ci" "apps" '[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]'
echo "=== library 项目：只拉（基础镜像） ==="
mk "jenkins-lib-pull" "library" '[{"resource":"repository","action":"pull"}]'

curl -s -u "$AH" "$H/api/v2.0/robots?page_size=100" | python3 -c 'import sys,json;[print(" robot:",r["name"],"id:",r["id"]) for r in json.load(sys.stdin)]'
