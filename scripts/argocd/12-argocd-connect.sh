#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config

echo "=== 1. 保存 GitLab 仓库凭据（Secret）==="
kubectl -n argocd create secret generic gitlab-repo-creds \
  --from-literal=username=root \
  --from-literal=password=__GITLAB_PAT__ \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret gitlab-repo-creds \
  argocd.argoproj.io/secret-type=repository --overwrite >/dev/null 2>&1 || true
# 给 secret 打上 repository 类型标签（声明式声明会读取该标签）
kubectl -n argocd patch secret gitlab-repo-creds --type merge \
  -p '{"metadata":{"labels":{"argocd.argoproj.io/secret-type":"repository"}},"stringData":{"type":"git","url":"http://192.168.200.12/root/cicd-demo.git"}}'

echo "=== 2. 创建 Application ==="
cat >/root/demo-app.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: http://192.168.200.12/root/cicd-demo.git
    targetRevision: main
    path: deploy
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
kubectl apply -f /root/demo-app.yaml

echo "=== 3. 等待 ArgoCD 完成同步 ==="
for i in $(seq 1 40); do
  sync=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}' 2>/dev/null)
  health=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.health.status}' 2>/dev/null)
  echo "[$((i*5))s] sync=$sync health=$health"
  [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ] && break
  sleep 5
done

echo "=== 4. 结果核对 ==="
kubectl -n argocd get application demo-app
kubectl -n demo get pods -o wide 2>&1
kubectl -n demo get svc 2>&1
echo "--- 服务访问 ---"
curl -sS -m 10 -o /dev/null -w "demo-nginx-http:%{http_code}\n" http://127.0.0.1:30081/ 2>&1
echo "--- ArgoCD 账户可查看的仓库 ---"
kubectl -n argocd get secret gitlab-repo-creds -o jsonpath='{.metadata.labels}'; echo
echo "=== CONNECT DONE ==="
