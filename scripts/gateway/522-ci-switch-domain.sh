#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
G=https://gitlab.corp.local/api/v4

echo "=== 1. 改 CI 变量 HARBOR_REGISTRY=harbor.corp.local ==="
curl -s -k -X PUT -H "PRIVATE-TOKEN: $PAT" \
  --data-urlencode "value=harbor.corp.local" \
  "$G/projects/2/variables/HARBOR_REGISTRY" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  ", d.get("key"), "=", d.get("value"))'

echo "=== 2. 改 ci/verify-image.sh 为 https ==="
OLD=$(curl -s -k -H "PRIVATE-TOKEN: $PAT" "$G/projects/2/repository/files/ci%2Fverify-image.sh/raw?ref=main")
NEW=$(printf '%s' "$OLD" | sed 's#"http://\$reg/v2#"https://$reg/v2#')
printf '%s' "$NEW" | grep -n 'https://$reg' | head -2
python3 - "$NEW" <<'PY'
import sys, json, urllib.parse, subprocess
content = sys.stdin.read()
body = json.dumps({
  "branch": "main",
  "commit_message": "ci: verify-image 改用 https 访问 Harbor（域名 + 内部 CA）",
  "content": content,
})
open("/tmp/commit_body.json","w").write(body)
PY
curl -s -k -X PUT -H "PRIVATE-TOKEN: $PAT" -H "Content-Type: application/json" \
  --data @/tmp/commit_body.json "$G/projects/2/repository/files/ci%2Fverify-image.sh" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  commit:", d.get("file_path"), d.get("branch"))'

echo "=== 3. 触发 pipeline（main） ==="
curl -s -k -X POST -H "PRIVATE-TOKEN: $PAT" "$G/projects/2/pipeline?ref=main" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  pipeline id:", d.get("id"), "status:", d.get("status"), "url:", d.get("web_url"))'
