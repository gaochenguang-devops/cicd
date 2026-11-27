#!/usr/bin/env bash
export KUBECONFIG=/root/.kube/config
echo "uptime: $(uptime -p) since $(uptime -s)"
for i in $(seq 1 60); do
  node=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
  gl=$(curl -sS -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1/users/sign_in 2>/dev/null)
  ar=$(curl -sS -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:30080/ 2>/dev/null)
  pods=$(kubectl -n demo get pods -l app=demo-nginx --no-headers 2>/dev/null | grep -c Running)
  echo "[$((i*10))s] node=${node:-down} gitlab=$gl argocd=$ar demo_pods=$pods"
  if [ "$node" = "Ready" ] && [ "$gl" = "200" ] && [ "$ar" = "200" ] && [ "$pods" = "2" ]; then
    echo "ALL RECOVERED"; break
  fi
  sleep 10
done

echo "=== 重启后状态明细 ==="
kubectl get nodes
kubectl -n argocd get application demo-app
kubectl -n demo get pods -l app=demo-nginx
gitlab-ctl status 2>/dev/null | awk '{print $1, $2}' | sed 's/:.*//' 
echo "--- 服务希望/自启 ---"
for s in containerd kubelet gitlab-runsvdir; do printf "%s=%s " $s "$(systemctl is-active $s)"; done; echo
echo "--- 内存 ---"
free -m | head -3
