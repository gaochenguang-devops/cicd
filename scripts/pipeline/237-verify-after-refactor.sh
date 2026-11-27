#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. deploy 分支最新提交 ====="
H="PRIVATE-TOKEN: __GITLAB_PAT__"
curl -s -H "$H" "http://127.0.0.1/api/v4/projects/2/repository/commits?ref_name=deploy&per_page=3" \
| python3 -c 'import json,sys;[print("  %s %s %s"%(c["short_id"],c["created_at"][11:19],c["title"])) for c in json.load(sys.stdin)]'

echo "===== 2. ArgoCD 应用状态 ====="
sleep 20
for a in podinfo webapp; do
kubectl -n argocd get application $a -o json | python3 -c '
import json,sys
d=json.load(sys.stdin); s=d.get("status",{})
print("  %-8s rev=%-8s deployed=%s %s/%s"%(d["metadata"]["name"], d["spec"]["source"]["targetRevision"],
      s.get("sync",{}).get("revision","")[:8], s.get("sync",{}).get("status"), s.get("health",{}).get("status")))
'
done

echo "===== 3. webhook 是否真的驱动了刷新 ====="
kubectl -n argocd logs deploy/argocd-server --since=8m | grep -E 'Received push event|Webhook handler' | tail -6 | sed 's/^/  /'

echo "===== 4. 集群实际镜像与 pod ====="
kubectl -n podinfo get deploy podinfo -o jsonpath='  podinfo image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n webapp get deploy -o custom-columns='  NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image'
kubectl -n podinfo get pods -o custom-columns='  POD:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,IMAGEID:.status.containerStatuses[0].imageID' | head -3

echo "===== 5. podinfo 自报的版本（REVISION 注入）====="
curl -s http://127.0.0.1:30095/info | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  version=%s revision=%s"%(d.get("version"),(d.get("revision") or "")[:8]))' 2>/dev/null || echo "  (取不到 /info)"
