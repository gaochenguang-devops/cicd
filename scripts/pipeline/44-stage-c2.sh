#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)

echo "---------------- TC-09 资源请求超限（8Gi > 节点可分配）：Pod 应 Pending 而非静默成功"
sed -i 's#memory: 64Mi#memory: 8Gi#' deploy/deployment.yaml
NEW=$(gpush "tc09: request 8Gi")
wait_rev demo-app "$NEW" 45 >/dev/null
REASON=""
for i in $(seq 1 20); do
  REASON=$(kubectl -n demo get pods -o json 2>/dev/null | jq -r '[.items[]? | select(.status.phase=="Pending") | (.status.conditions[]?|select(.type=="PodScheduled").message)] | join(";")')
  [ -n "$REASON" ] && break
  sleep 4
done
echo "    - Pending 原因: ${REASON:-none}"
echo "$REASON" | grep -qi "insufficient" && ok "TC-09a 调度失败可诊断" "$(echo $REASON | head -c 80)" || ng "TC-09a 调度失败可诊断" "[$REASON]"
assert_eq "TC-09b 旧副本仍服务" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30081/)" "200"
info "ArgoCD health=$(APP_HEALTH demo-app) sync=$(APP_SYNC demo-app)"
git -C $REPO_DIR checkout -q "$BASE" -- .
cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "tc09 restore" >/dev/null 2>&1 && git push -q origin main 2>&1|tail -1
wait_rev demo-app "$(git rev-parse HEAD)" 60 >/dev/null
wait_health demo-app Healthy 120 >/dev/null && ok "TC-09c 恢复后健康" "Healthy" || ng "TC-09c 恢复后健康" "$(APP_HEALTH demo-app)"
echo

echo "---------------- TC-10 全新命名空间 + 独立应用：CreateNamespace 自动建 ns，删除应用级联清理"
mkdir -p deploy2
cat > deploy2/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML
cat > deploy2/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo2-nginx
  labels:
    app: demo2-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo2-nginx
  template:
    metadata:
      labels:
        app: demo2-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          resources:
            requests:
              cpu: 30m
              memory: 32Mi
YAML
NEW=$(gpush "tc10: add deploy2 for new namespace")
cat > /root/cicd-test/app-demo2.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app2
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://192.168.200.12/root/cicd-demo.git
    targetRevision: main
    path: deploy2
  destination:
    server: https://kubernetes.default.svc
    namespace: demo2
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
kubectl apply -f /root/cicd-test/app-demo2.yaml >/dev/null
sleep 8
if kubectl get ns demo2 >/dev/null 2>&1; then ok "TC-10a 命名空间自动创建" "ns/demo2 已创建"; else ng "TC-10a 命名空间自动创建" "ns/demo2 不存在"; fi
if wait_health demo-app2 Healthy 120; then ok "TC-10b 新应用部署成功" "Synced/Healthy，Pod 运行"; else ng "TC-10b 新应用部署成功" "$(APP_SYNC demo-app2)/$(APP_HEALTH demo-app2)"; fi
kubectl -n demo2 get pods --no-headers 2>/dev/null | head -2
echo "    - 删除应用（级联）"
api_delete=$(curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" "$API/api/v1/applications/demo-app2?cascade=true&propagationPolicy=foreground" -w '%{http_code}')
info "delete api http=$api_delete"
sleep 10
kubectl -n demo2 get deploy demo2-nginx >/dev/null 2>&1 && ng "TC-10c 级联清理资源" "deployment 仍存在" || ok "TC-10c 级联清理资源" "deployment 已删除"
kubectl get ns demo2 >/dev/null 2>&1 && info "ns/demo2 仍保留（ArgoCD 默认不删命名空间，符合预期）"
git -C $REPO_DIR checkout -q "$BASE" -- . 2>/dev/null
rm -rf deploy2
cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "tc10 cleanup" >/dev/null 2>&1 && git push -q origin main 2>&1|tail -1
wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null
cd $REPO_DIR && git status --short | head -3
echo "应用列表: $(api_get /api/v1/applications | jq -r '.items[].metadata.name' | tr '\n' ' ')"
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
