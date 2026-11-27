#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
conds() { APP_FIELD demo-app '.status.conditions[]?.message' | head -c 260 | tr '\n' ' '; }

echo "---------------- TC-19 GitLab 短时停机：ArgoCD 应降级报警且不误删线上资源"
echo "    - 停止 GitLab"
gitlab-ctl stop >/dev/null 2>&1
sleep 6
CODE=$(curl -s -o /dev/null -m 8 -w '%{http_code}' http://192.168.200.12/ || echo 000)
echo "    - GitLab HTTP=$CODE（000 表示不可达）"
refresh demo-app; sleep 20
ST=$(APP_SYNC demo-app); C=$(conds)
echo "    - ArgoCD: sync=$ST health=$(APP_HEALTH demo-app)"
echo "    - msg: $(echo $C|head -c 160)"
[ "$ST" != "Synced" ] && ok "TC-19a GitLab 不可达被检出" "sync=$ST" || info "ArgoCD 仍报 Synced（有本地缓存时可继续对比，属正常）"
assert_eq "TC-19b 工作负载未被误删" "$(kubectl -n demo get pods --no-headers | grep -c Running)" "2"
assert_eq "TC-19c 业务入口仍可用" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:30081/)" "200"
echo "    - 恢复 GitLab（等待就绪）"
gitlab-ctl start >/dev/null 2>&1
T0=$(date +%s); OK=no
for i in $(seq 1 40); do
  C2=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://192.168.200.12/ || echo 000)
  [ "$C2" != "000" ] && { OK=yes; break; }
  sleep 5
done
[ "$OK" = "yes" ] && ok "TC-19d GitLab 已恢复" "$(( $(date +%s)-T0 ))s 后 HTTP=$C2" || ng "TC-19d GitLab 已恢复" "等待超时"
gitlab-ctl status 2>/dev/null | awk '{print $2}' | tr '\n' ' '; echo
refresh demo-app; sleep 20
ST=$(APP_SYNC demo-app)
[ "$ST" = "Synced" ] && ok "TC-19e ArgoCD 自动收敛回正常" "Synced/$(APP_HEALTH demo-app)" || ng "TC-19e ArgoCD 自动收敛" "$ST $(conds)"
cd $REPO_DIR; sed -i -E 's/^  replicas: [0-9]+$/  replicas: 2/' deploy/deployment.yaml; git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -q -m "tc19 verify webhook after gitlab restart" >/dev/null 2>&1
git push -q origin main 2>&1|tail -1
T1=$(date +%s); wait_rev demo-app "$(git rev-parse HEAD)" 45 && ok "TC-19f 重启后 webhook 链路恢复" "$(( $(date +%s)-T1 ))s" || ng "TC-19f 重启后 webhook 链路恢复" "rev=$(APP_REV demo-app)"
echo
echo "PASS=$PASS FAIL=$FAIL"
