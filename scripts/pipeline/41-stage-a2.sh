#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)
reset_repo() {
  cd $REPO_DIR
  git checkout -q "$BASE" -- .
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -q -m "reset to base" >/dev/null 2>&1
  git push -q origin main 2>&1 | tail -1
  sleep 5
}
cond_type() { APP_FIELD demo-app '.status.conditions[]?.type' | tr '\n' ' '; }

echo "---------------- TC-03a 配置不自洽（删文件但未更新 kustomization）应被 ArgoCD 拦截"
git rm -q deploy/service.yaml
NEW=$(gpush "tc03a: delete service.yaml without kustomization update")
sleep 4; refresh demo-app; sleep 12
CT=$(cond_type); ST=$(APP_SYNC demo-app)
if echo "$CT" | grep -q ComparisonError; then
  ok "TC-03a 检出配置不自洽" "conditions=[$CT] sync=$ST"
else
  ng "TC-03a 检出配置不自洽" "conditions=[$CT] sync=$ST"
fi
if kubectl -n demo get svc demo-nginx >/dev/null 2>&1; then
  ok "TC-03a 保护性失败：未误删线上资源" "Service 仍在（ComparisonError 时不做任何变更）"
else
  ng "TC-03a 保护性失败" "Service 被删除"
fi
reset_repo
wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null
echo

echo "---------------- TC-03b 正确做法：删文件并同步更新 kustomization → prune 生效"
git rm -q deploy/service.yaml
sed -i '/- service.yaml/d' deploy/kustomization.yaml
NEW=$(gpush "tc03b: delete service.yaml and update kustomization")
if wait_rev demo-app "$NEW" 45; then
  ok "TC-03b 删除提交已同步" "$(date +%T) rev=${NEW:0:7} sync=$(APP_SYNC demo-app)"
else
  ng "TC-03b 删除提交已同步" "rev=$(APP_REV demo-app) cond=$(cond_type)"
fi
sleep 6
if kubectl -n demo get svc demo-nginx >/dev/null 2>&1; then
  ng "TC-03b Service 被 prune" "Service 仍存在，sync=$(APP_SYNC demo-app)"
else
  ok "TC-03b Service 被 prune" "demo-nginx Service 已回收"
fi
reset_repo
wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null
kubectl -n demo get svc demo-nginx --no-headers 2>/dev/null | head -1
echo

echo "---------------- TC-05 关闭自动同步：push 后只显示不同步，不实际部署"
kubectl -n argocd patch application demo-app --type=merge -p '{"spec":{"syncPolicy":null}}' >/dev/null
sleep 4
echo "    - 当前 syncPolicy: $(APP_FIELD demo-app '.spec.syncPolicy // "null"')"
sed -i 's/^  replicas: 2$/  replicas: 3/' deploy/deployment.yaml
NEW=$(gpush "tc05: replicas -> 3, autosync disabled")
sleep 20
ST=$(APP_SYNC demo-app); REP=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')
[ "$ST" = "Synced" ] && ng "TC-05a 未自动部署" "sync=$ST（仍在自动同步）" || ok "TC-05a 未自动部署" "20s 后 sync=$ST，符合预期"
assert_eq "TC-05b 集群保持旧状态" "$REP" "2"
sync_app demo-app >/dev/null; T0=$(date +%s)
if wait_rev demo-app "$NEW" 45; then ok "TC-05c 手动 Sync 生效" "$(( $(date +%s)-T0 ))s 后 rev=${NEW:0:7}"; else ng "TC-05c 手动 Sync 生效" "rev=$(APP_REV demo-app)"; fi
sleep 8
assert_eq "TC-05d 手动 Sync 后副本" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')" "3"
kubectl -n argocd patch application demo-app --type=merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}' >/dev/null
sleep 2
echo "    - syncPolicy 已恢复: $(APP_FIELD demo-app '.spec.syncPolicy.automated')"
reset_repo
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
