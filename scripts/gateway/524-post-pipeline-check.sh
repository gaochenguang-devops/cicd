#!/bin/bash
set -uo pipefail
echo "=== ArgoCD 应用同步状态 ==="
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
echo "=== podinfo / webapp pods 与镜像 ==="
kubectl get pods -n podinfo -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:..image --no-headers
kubectl get pods -n webapp -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:..image --no-headers
echo "=== deploy 分支最新提交 ==="
curl -s -k -H "PRIVATE-TOKEN: __GITLAB_PAT__" "https://gitlab.corp.local/api/v4/projects/2/repository/commits?ref_name=deploy&per_page=2" | python3 -c 'import sys,json;[print("  ",c["short_id"],c["title"]) for c in json.load(sys.stdin)]'
echo "=== Harbor 最新 tag（域名仓库） ==="
curl -s -k -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects/apps/repositories/podinfo/artifacts?page_size=3&with_tag=true" | python3 -c '
import sys,json
for a in json.load(sys.stdin): print("  ", [t["name"] for t in (a.get("tags") or [])], a["push_time"][:19])
'
echo "=== 事件里是否有拉取失败 ==="
kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | grep -iE "failed|pull|back-off" | tail -5 || echo "  无"
