#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config

echo "=== 下载 ArgoCD v3.5.9 官方 install.yaml ==="
curl -sSL --retry 3 -m 180 -o /root/argocd-install.yaml \
  https://cdn.jsdelivr.net/gh/argoproj/argo-cd@v3.5.9/manifests/install.yaml
grep -c "kind:" /root/argocd-install.yaml

echo "=== 创建命名空间并部署 ==="
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f /root/argocd-install.yaml 2>&1 | tail -15

echo "=== 关闭 TLS（8080 走 http），暴露 NodePort 30080 ==="
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd patch svc argocd-server -p \
  '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080}]}}'
kubectl -n argocd rollout restart deployment argocd-server >/dev/null 2>&1 || true

echo "=== 等待 ArgoCD 组件就绪（最多 8 分钟）==="
for i in $(seq 1 48); do
  notready=$(kubectl -n argocd get pods --no-headers 2>/dev/null | grep -vE "Running|Completed" | wc -l)
  total=$(kubectl -n argocd get pods --no-headers 2>/dev/null | wc -l)
  echo "[$((i*10))s] pods=$total not-ready=$notready"
  [ "$total" -ge 7 ] && [ "$notready" -eq 0 ] && break
  sleep 10
done
kubectl -n argocd get pods -o wide
kubectl -n argocd get svc argocd-server

echo "=== 初始化 admin 密码 ==="
PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
echo "ArgoCD 初始 admin 口令已写入 /root/.argocd-admin-password（600），不回显"
echo "$PW" > /root/.argocd-admin-password
chmod 600 /root/.argocd-admin-password

echo "=== 访问测试 ==="
sleep 5
curl -sS -m 15 -o /dev/null -w "argocd-http:%{http_code}\n" http://127.0.0.1:30080/ 2>&1
echo "=== ARGOCD DONE ==="
