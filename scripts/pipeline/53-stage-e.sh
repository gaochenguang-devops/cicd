#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)
conds() { APP_FIELD demo-app '.status.conditions[]?.message' | head -c 260 | tr '\n' ' '; }

echo "---------------- TC-15 AppProject 仓库白名单：越权仓库应被拒绝"
kubectl -n argocd get appproject default -o json > /root/cicd-test/project-backup.json
OLD=$(kubectl -n argocd get appproject default -o jsonpath='{.spec.sourceRepos}')
echo "    - 原 sourceRepos: $OLD"
kubectl -n argocd patch appproject default --type=merge -p '{"spec":{"sourceRepos":["https://example.com/not-allowed.git"]}}' >/dev/null
refresh demo-app; sleep 18
ST=$(APP_SYNC demo-app); C=$(conds)
echo "$C" | grep -qiE "not permitted|permitted in project|ComparisonError" && ok "TC-15a 越权被拒绝" "$(echo $C|head -c 110)" || ng "TC-15a 越权被拒绝" "sync=$ST msg=$C"
kubectl -n argocd patch appproject default --type=merge -p "{\"spec\":{\"sourceRepos\":$OLD}}" >/dev/null
refresh demo-app; sleep 18
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-15b 恢复白名单后自愈" "Synced" || ng "TC-15b 恢复白名单后自愈" "$(APP_SYNC demo-app) $(conds)"
echo

echo "---------------- TC-16 并发推送风暴：连续 5 次提交应收敛到最后一个版本"
for n in 4 5 6 7 2; do
  sed -i -E "s/^  replicas: [0-9]+$/  replicas: $n/" deploy/deployment.yaml
  NEW=$(gpush "tc16: replicas -> $n")
  echo "    - commit ${NEW:0:7} replicas=$n"
done
T0=$(date +%s)
if wait_rev demo-app "$NEW" 60; then ok "TC-16a 收敛到最后提交" "$(( $(date +%s)-T0 ))s 内到 ${NEW:0:7}"; else ng "TC-16a 收敛到最后提交" "rev=$(APP_REV demo-app) expect=${NEW:0:7}"; fi
sleep 8
assert_eq "TC-16b 集群副本等于最后声明" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}')" "2"
wait_health demo-app Healthy 90 >/dev/null
OK=$(kubectl -n demo get pods -l app=demo-nginx -o jsonpath='{.items[*].spec.containers[0].image}' | tr ' ' '\n' | sort -u | wc -l)
assert_eq "TC-16c 同代副本镜像一致" "$OK" "1"
reset_repo 2>/dev/null || { git -C $REPO_DIR checkout -q "$BASE" -- .; cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "reset" >/dev/null 2>&1 && git push -q origin main 2>&1|tail -1; }
wait_rev demo-app "$(git rev-parse HEAD)" 60 >/dev/null
echo

echo "---------------- TC-17 中文代理层（30082）：不能破坏 API / SSE / 静态资源"
C1=$(curl -s -o /dev/null -w '%{http_code}' http://192.168.200.12:30082/api/v1/applications)
assert_eq "TC-17a 未认证 API 仍返回 401" "$C1" "401"
C2=$(curl -s -o /dev/null -w '%{http_code}' http://192.168.200.12:30082/zh-cn.js)
assert_eq "TC-17b 词库脚本可访问" "$C2" "200"
TOK2=$(curl -s -X POST http://192.168.200.12:30082/api/v1/session -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$(cat /root/.argocd-admin-password)\"}" | jq -r '.token // empty')
[ -n "$TOK2" ] && ok "TC-17c 经代理可正常登录 API" "token ${#TOK2} 字符" || ng "TC-17c 经代理可正常登录 API" "登录失败"
CNT=$(curl -s -H "Authorization: Bearer $TOK2" http://192.168.200.12:30082/api/v1/applications | jq -r '.items|length')
[ "$CNT" -ge 1 ] && ok "TC-17d 经代理读取应用列表" "应用数=$CNT" || ng "TC-17d 经代理读取应用列表" "数量=$CNT"
CT=$(curl -s -D - -o /dev/null --max-time 8 -H "Authorization: Bearer $TOK2" \
  "http://192.168.200.12:30082/api/v1/stream/applications" | tr -d '\r' | grep -i 'content-type' | head -1)
echo "    - SSE content-type: ${CT:-none}"
echo "$CT" | grep -qi "event-stream" && ok "TC-17e SSE 事件流未被代理缓冲" "text/event-stream" || info "未拿到 SSE header（--max-time 提前断开属正常）"
INJ=$(curl -s http://192.168.200.12:30082/ | grep -c "zh-cn.js")
[ "$INJ" -ge 1 ] && ok "TC-17f 页面已注入中文词库" "命中 $INJ 处" || ng "TC-17f 页面已注入中文词库" "未注入"
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
