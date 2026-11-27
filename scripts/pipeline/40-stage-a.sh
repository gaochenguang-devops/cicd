#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(git rev-parse HEAD)
echo "$BASE" > /root/cicd-test/base.txt
echo "BASE=${BASE:0:7}  app: $(APP_SYNC demo-app)/$(APP_HEALTH demo-app) rev=$(APP_REV demo-app) $(APP_REV demo-app | head -c 7)"
echo

reset_repo() {
  cd $REPO_DIR
  git checkout -q "$BASE" -- . 2>/dev/null
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -q -m "reset to base" >/dev/null 2>&1
  git push -q origin main 2>&1 | tail -1
  sleep 3
}
podready() { kubectl -n demo get pods -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c True; }

echo "---------------- TC-01 基线：GitLab HEAD 与 ArgoCD 同步版本一致"
REV=$(APP_REV demo-app); ST=$(APP_SYNC demo-app); HL=$(APP_HEALTH demo-app)
REP=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}' 2>/dev/null)
[ "${REV:0:7}" = "${BASE:0:7}" ] && ok "TC-01a 版本一致" "argocd=${REV:0:7} gitlab=${BASE:0:7}" || ng "TC-01a 版本一致" "argocd=$REV gitlab=${BASE:0:7}"
[ "$ST" = "Synced" ]   && ok "TC-01b 同步状态" "$ST" || ng "TC-01b 同步状态" "$ST"
[ "$HL" = "Healthy" ]  && ok "TC-01c 健康状态" "$HL" || ng "TC-01c 健康状态" "$HL"
[ "$REP" = "2" ]       && ok "TC-01d 副本数" "2" || ng "TC-01d 副本数" "$REP"
echo

echo "---------------- TC-02 Webhook 推送触发自动同步"
sed -i 's/^  replicas: 2$/  replicas: 3/' deploy/deployment.yaml
NEW=$(gpush "tc02: replicas -> 3")
T0=$(date +%s)
if wait_rev demo-app "$NEW" 45; then
  ok "TC-02a webhook 触发同步" "$(( $(date +%s)-T0 ))s 内同步到 ${NEW:0:7}"
else
  ng "TC-02a webhook 触发同步" "45s 未同步，rev=$(APP_REV demo-app) expect=${NEW:0:7}"
fi
sleep 6
REP=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')
RDY=$(podready)
assert_eq "TC-02b 集群实际副本" "$REP" "3"
echo "    - 就绪 Pod 数=$RDY"
reset_repo
wait_rev demo-app "$(cd $REPO_DIR && git rev-parse HEAD)" 45 >/dev/null && info "已复位到基线"
echo

echo "---------------- TC-03 prune=true：仓库删文件后集群资源应被回收"
cd $REPO_DIR
git rm -q deploy/service.yaml
NEW=$(gpush "tc03: remove service.yaml (prune test)")
if wait_rev demo-app "$NEW" 45; then ok "TC-03a 删除提交已同步" "${NEW:0:7}"; else ng "TC-03a 删除提交已同步" "rev=$(APP_REV demo-app)"; fi
sleep 5
if kubectl -n demo get svc demo-nginx >/dev/null 2>&1; then
  ng "TC-03b Service 被 prune" "Service 仍存在"
else
  ok "TC-03b Service 被 prune" "demo-nginx Service 已回收"
fi
reset_repo
wait_rev demo-app "$(cd $REPO_DIR && git rev-parse HEAD)" 45 >/dev/null && info "已复位，Service 恢复"
kubectl -n demo get svc demo-nginx --no-headers 2>/dev/null | head -1
echo

echo "---------------- TC-04 selfHeal：集群被手工改动应自动收敛回 Git 声明状态"
kubectl -n demo scale deploy demo-nginx --replicas=1 >/dev/null
echo "    - 手工 scale 到 1，等待 selfHeal"
T0=$(date +%s); HEALED=no
for i in $(seq 1 20); do
  R=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')
  [ "$R" = "2" ] && { HEALED=yes; break; }
  sleep 3
done
DT=$(( $(date +%s)-T0 ))
[ "$HEALED" = "yes" ] && ok "TC-04 selfHeal 生效" "${DT}s 内副本从 1 回到 2" || ng "TC-04 selfHeal 生效" "60s 内未回滚，当前=$R"
echo

echo "---------------- TC-05 自动同步关闭后：push 不应自动部署，手动 sync 才生效"
kubectl -n argocd get application demo-app -o json > /root/cicd-test/app-backup.json
kubectl -n argocd patch application demo-app --type=merge -p '{"spec":{"syncPolicy":null}}' >/dev/null
sleep 3
sed -i 's/^  replicas: 2$/  replicas: 3/' deploy/deployment.yaml
NEW=$(gpush "tc05: replicas -> 3 with autosync off")
sleep 20
ST=$(APP_SYNC demo-app); REV=$(APP_REV demo-app)
[ "${REV:0:7}" != "${NEW:0:7}" ] && ok "TC-05a 自动同步关闭后未自动部署" "rev 仍为 ${REV:0:7} status=$ST" || ng "TC-05a 自动同步关闭" "仍被自动同步"
sleep 2
kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}' | grep -q 2 && ok "TC-05b 集群保持旧状态" "replicas=2" || ng "TC-05b 集群保持旧状态" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')"
sync_app demo-app >/dev/null; T0=$(date +%s)
wait_rev demo-app "$NEW" 45 && ok "TC-05c 手动 Sync 立即生效" "$(( $(date +%s)-T0 ))s" || ng "TC-05c 手动 Sync 立即生效" "rev=$(APP_REV demo-app)"
sleep 5
assert_eq "TC-05d 手动 Sync 后副本" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')" "3"
# 恢复自动同步
kubectl apply -f <(kubectl -n argocd get application demo-app -o json | jq '.spec.syncPolicy={"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}' | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.generation,.metadata.creationTimestamp,.metadata.managedFields)') >/dev/null 2>&1
sleep 2
echo "    - syncPolicy 恢复后: $(APP_FIELD demo-app '.spec.syncPolicy.automated')"
reset_repo
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
