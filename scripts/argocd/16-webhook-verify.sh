#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
cd /root/work/cicd-demo
sed -i 's/replicas: 3/replicas: 4/' deploy/deployment.yaml
git commit -qam "scale demo-nginx to 4 replicas via webhook test"
T0=$(date +%s)
git push -q origin main
echo "pushed rev=$(git rev-parse --short HEAD) at $(date +%T)"

echo "=== 观察同步延迟 ==="
for i in $(seq 1 40); do
  sync=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}')
  rev=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.revision}' | cut -c1-8)
  n=$(kubectl -n demo get pods -l app=demo-nginx --no-headers 2>/dev/null | wc -l)
  echo "[+$(( $(date +%s) - T0 ))s] sync=$sync rev=$rev pods=$n"
  [ "$n" = "4" ] && [ "$sync" = "Synced" ] && break
  sleep 3
done

echo "=== webhook 投递记录 ==="
TOKEN=__GITLAB_PAT__
curl -sS -m 15 "http://192.168.200.12/api/v4/projects/1/hooks/1" -H "PRIVATE-TOKEN: $TOKEN" \
 | python3 -c "import json,sys; d=json.load(sys.stdin); print('url=',d['url'],'push_events=',d['push_events'],'alert=',d.get('alert_status'))"
echo "=== 最终状态 ==="
kubectl -n demo get pods -l app=demo-nginx
kubectl -n argocd get application demo-app
