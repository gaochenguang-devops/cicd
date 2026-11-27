#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config

echo "=== 复位 demo 副本为 2 ==="
cd /root/work/cicd-demo
sed -i 's/replicas: 4/replicas: 2/' deploy/deployment.yaml
git commit -qam "reset demo-nginx replicas to 2"
git push -q origin main
sleep 6
kubectl -n demo get pods -l app=demo-nginx | head -5

echo ""
echo "=== 版本清单 ==="
echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "containerd: $(containerd --version | awk '{print $3}')"
echo "kubelet/kubectl: $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')"
echo "GitLab: $(gitlab-ctl version 2>/dev/null | awk '{print $2}')"
ARGOVER=$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $2}')
echo "ArgoCD: $ARGOVER"
echo "Calico: $(kubectl -n kube-system get ds calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $2}')"

echo ""
echo "=== 访问信息 ==="
echo "GitLab Web : http://192.168.200.12  (root / 口令见 .env: GITLAB_ROOT_PASS)"
echo "GitLab SSH : 未启用（HTTP git 可用，见文档）"
echo "ArgoCD Web : http://192.168.200.12:30080  (admin / 口令见 /root/.argocd-admin-password)"
echo "Demo App   : http://192.168.200.12:30081"
echo "K8s API    : https://192.168.200.12:6443"

echo ""
echo "=== 健康检查 ==="
kubectl get nodes
kubectl -n argocd get pods --no-headers | awk '{print $1, $2, $3}' | column -t
gitlab-ctl status 2>/dev/null | awk '{print $2, $3}' | sed 's/://' | column -t
echo "--- NodePort 探活 ---"
curl -sS -m 8 -o /dev/null -w "gitlab:%{http_code} " http://127.0.0.1/users/sign_in
curl -sS -m 8 -o /dev/null -w "argocd:%{http_code} " http://127.0.0.1:30080/
curl -sS -m 8 -o /dev/null -w "demo:%{http_code}\n" http://127.0.0.1:30081/

echo ""
echo "=== 资源占用 ==="
free -m | head -3
df -h / | tail -1
echo "--- top 内存进程 ---"
ps -eo rss,comm --sort=-rss | head -8
