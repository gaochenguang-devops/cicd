#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
echo "=== GitLab CI/CD variables（root/podinfo id=2） ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/variables?per_page=50" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for v in d: print("  ", v["key"], "=", v["value"], "[protected]" if v.get("protected") else "")
'
echo "=== .gitlab-ci.yml（main） ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/files/.gitlab-ci.yml/raw?ref=main" | grep -nE "HARBOR|image|deploy|manifest|sed|PODINFO" | head -40
echo "=== deploy 分支清单里的镜像引用 ==="
for f in $(curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/tree?ref=deploy&recursive=true&per_page=100" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(" ".join(x["path"] for x in d if x["path"].endswith((".yaml",".yml"))))'); do
  echo "--- $f"
  curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/files/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$f")/raw?ref=deploy" | grep -nE "image:|192\.168\.200\.12:30090|harbor" | head -6
done
