#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
cd /root/work/cicd-demo
sed -i 's/replicas: 2/replicas: 3/' deploy/deployment.yaml
git commit -qam "post-reboot webhook check: 3 replicas"
T0=$(date +%s); git push -q origin main
echo "push rev=$(git rev-parse --short HEAD) at $(date +%T)"
for i in $(seq 1 30); do
  n=$(kubectl -n demo get pods -l app=demo-nginx --no-headers 2>/dev/null | wc -l)
  s=$(kubectl -n argocd get app demo-app -o jsonpath='{.status.sync.status}')
  echo "[+$(( $(date +%s) - T0 ))s] sync=$s pods=$n"
  [ "$n" = "3" ] && break
  sleep 3
done
echo "=== 复位为 2 ==="
sed -i 's/replicas: 3/replicas: 2/' deploy/deployment.yaml
git commit -qam "reset to 2 replicas"; git push -q origin main
sleep 8
kubectl -n argocd get app demo-app; kubectl -n demo get pods -l app=demo-nginx
echo "=== 最终资源 ==="
free -m | head -3; df -h / | tail -1
