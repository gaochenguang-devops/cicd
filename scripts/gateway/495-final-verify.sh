#!/bin/bash
set -uo pipefail
echo "=== 网关 error.log 最近 502/上游错误 ==="
kubectl -n gateway logs deploy/gateway --tail=200 2>&1 | grep -iE "502|failed|110|111|connect\(\)" | tail -8 || echo "  无"
echo "=== dex 日志错误 ==="
kubectl -n argocd logs deploy/argocd-dex-server --tail=30 2>&1 | grep -iE "error|fail|oidc" | tail -6 || echo "  无"
echo "=== 触发一次 GitLab CI（验证 runner 走 https 克隆） ==="
curl -s -X POST -H "PRIVATE-TOKEN: __GITLAB_PAT__" \
  "http://192.168.200.12/api/v4/projects/2/pipeline" -d "ref=main" | head -c 300; echo
sleep 45
curl -s -H "PRIVATE-TOKEN: __GITLAB_PAT__" "http://192.168.200.12/api/v4/projects/2/pipelines?per_page=1" | python3 -c '
import json,sys
d=json.load(sys.stdin)
if d:
    p=d[0]; print("  pipeline #%s status=%s ref=%s" % (p["iid"], p["status"], p["ref"]))
'
curl -s -H "PRIVATE-TOKEN: __GITLAB_PAT__" "http://192.168.200.12/api/v4/projects/2/pipelines?per_page=1" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  url:", d[0]["web_url"] if d else "-")
'
