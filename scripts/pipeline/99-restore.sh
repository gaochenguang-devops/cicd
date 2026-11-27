#!/usr/bin/env bash
# 测试现场复位：仓库回基线、webhook 开启、PAT/白名单/同步策略复原、清理测试应用与命名空间
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
echo "== 1. 清理测试应用 demo-app2 / ns demo2 =="
kubectl -n argocd delete application demo-app2 --ignore-not-found --wait=false >/dev/null 2>&1
kubectl -n demo2 delete deploy --all --ignore-not-found >/dev/null 2>&1
kubectl delete ns demo2 --ignore-not-found >/dev/null 2>&1
echo "   应用的: $(api_get /api/v1/applications | jq -r '.items[].metadata.name' | tr '\n' ' ')"

echo "== 2. 恢复 syncPolicy（automated prune+selfHeal）=="
kubectl -n argocd patch application demo-app --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}' >/dev/null

echo "== 3. 恢复 AppProject 白名单 =="
kubectl -n argocd patch appproject default --type=merge -p '{"spec":{"sourceRepos":["*"]}}' >/dev/null

echo "== 4. 恢复 Git 凭据为主 PAT =="
kubectl -n argocd patch secret gitlab-repo-creds --type=merge \
  -p "{\"data\":{\"password\":\"$(printf '%s' "$GL_TOKEN" | base64 -w0)\"}}" >/dev/null

echo "== 5. 恢复 webhook push 事件 =="
HID=$(curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks" | jq -r '.[0].id // empty')
if [ -n "$HID" ]; then
  curl -s -o /dev/null -X PUT -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks/$HID?push_events=true"
  curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks" | jq -r '.[]|"   hook \(.id) push=\(.push_events) url=\(.url)"'
fi

echo "== 6. 仓库回基线 =="
BASE=$(cat /root/cicd-test/base.txt 2>/dev/null || (cd $REPO_DIR && git rev-parse HEAD))
cd $REPO_DIR
git checkout -q "$BASE" -- . 2>/dev/null
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -q -m "restore: test cleanup" >/dev/null 2>&1
git push -q origin main 2>&1 | tail -1

echo "== 7. 清 repo-server 缓存并触发刷新 =="
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server >/dev/null 2>&1
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=150s >/dev/null 2>&1
refresh demo-app
sleep 20

echo "== 最终状态 =="
echo "  app: $(APP_SYNC demo-app)/$(APP_HEALTH demo-app) rev=$(APP_REV demo-app | head -c 7) git=$(git rev-parse HEAD | head -c 7)"
echo "  replicas=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}') pods=$(kubectl -n demo get pods --no-headers 2>/dev/null | grep -c Running)"
echo "  svc=$(kubectl -n demo get svc demo-nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null) http=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30081/)"
echo "  内存: $(free -m | awk '/Mem:/{print $3"MB used / "$2"MB total"}')"
