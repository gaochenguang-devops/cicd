#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)
conds() { APP_FIELD demo-app '.status.conditions[]? | "\(.type):\(.message)"' | tr '\n' '|'; }
restore_app() {
  kubectl -n argocd patch application demo-app --type=merge \
    -p '{"spec":{"source":{"repoURL":"http://192.168.200.12/root/cicd-demo.git","targetRevision":"main","path":"deploy"}}}' >/dev/null
  refresh demo-app; sleep 10
}
wait_ok() { wait_rev demo-app "$(cd $REPO_DIR && git rev-parse HEAD)" 90 >/dev/null; wait_health demo-app Healthy 120 >/dev/null; }

echo "---------------- TC-11 Git 凭据失效：ArgoCD 应报鉴权失败而非静默用旧缓存"
PWB64=$(kubectl -n argocd get secret gitlab-repo-creds -o jsonpath='{.data.password}')
kubectl -n argocd patch secret gitlab-repo-creds --type=merge \
  -p "{\"data\":{\"password\":\"$(printf 'wrong-pass-123' | base64 -w0)\"}}" >/dev/null
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server --wait=false >/dev/null
sleep 25
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=120s >/dev/null 2>&1
refresh demo-app; sleep 12
C=$(conds); ST=$(APP_SYNC demo-app)
if echo "$C" | grep -qiE "ComparisonError"; then ok "TC-11a 鉴权失败被暴露" "$(echo $C | head -c 120)"; else ng "TC-11a 鉴权失败被暴露" "conditions=[$C] sync=$ST"; fi
info "sync=$ST health=$(APP_HEALTH demo-app)"
kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}' | grep -q 2 && ok "TC-11b 凭据故障不影响已部署工作负载" "readyReplicas=2" || ng "TC-11b 工作负载保持" "ready=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}')"
# 恢复
kubectl -n argocd patch secret gitlab-repo-creds --type=merge -p "{\"data\":{\"password\":\"$PWB64\"}}" >/dev/null
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server --wait=false >/dev/null
sleep 25; kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=120s >/dev/null 2>&1
refresh demo-app; wait_ok
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-11c 恢复凭据后自愈" "Synced/$(APP_HEALTH demo-app)" || ng "TC-11c 恢复凭据后自愈" "$(APP_SYNC demo-app)/$(APP_HEALTH demo-app) $(conds)"
echo

echo "---------------- TC-12 目标分支不存在：应为明确对比错误，且不清空现有资源"
kubectl -n argocd patch application demo-app --type=merge -p '{"spec":{"source":{"targetRevision":"branch-does-not-exist"}}}' >/dev/null
refresh demo-app; sleep 12
C=$(conds); ST=$(APP_SYNC demo-app)
echo "$C" | grep -qiE "unable to resolve|ComparisonError|does not exist" && ok "TC-12a 分支不存在被检出" "$(echo $C|head -c 120)" || ng "TC-12a 分支不存在被检出" "[$C] sync=$ST"
assert_eq "TC-12b 现有 Pod 不受影响" "$(kubectl -n demo get pods --no-headers | grep -c Running)" "2"
restore_app
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-12c 恢复分支后自愈" "Synced" || ng "TC-12c 恢复分支后自愈" "$(APP_SYNC demo-app) $(conds)"
echo

echo "---------------- TC-13 非法 YAML（缩进错误）：构建失败应阻断同步，不产生半套资源"
cp deploy/deployment.yaml /tmp/deploy.bak
sed -i 's/^    app: demo-nginx$/     app: demo-nginx/' deploy/deployment.yaml
NEW=$(gpush "tc13: broken yaml indentation")
refresh demo-app; sleep 14
C=$(conds); ST=$(APP_SYNC demo-app)
echo "$C" | grep -qiE "ComparisonError|yaml|parse|error" && ok "TC-13a 非法清单被拒绝" "$(echo $C|head -c 130)" || ng "TC-13a 非法清单被拒绝" "[$C] sync=$ST"
assert_eq "TC-13b 线上副本未被削减" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}')" "2"
cp /tmp/deploy.bak deploy/deployment.yaml
cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "tc13 restore" >/dev/null 2>&1 && git push -q origin main 2>&1|tail -1
wait_ok
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-13c 修复后恢复同步" "Synced/$(APP_HEALTH demo-app)" || ng "TC-13c 修复后恢复同步" "$(APP_SYNC demo-app) $(conds)"
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
