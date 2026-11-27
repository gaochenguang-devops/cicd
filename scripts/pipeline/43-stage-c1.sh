#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)

echo "---------------- TC-08 错误镜像 tag（生产最常见事故）：旧副本是否仍在服务、ArgoCD 能否感知"
sed -i 's#nginx:1.27-alpine#nginx:9.9.9-not-exist#' deploy/deployment.yaml
NEW=$(gpush "tc08: bad image tag")
wait_rev demo-app "$NEW" 45 && info "已同步 ${NEW:0:7}" || info "同步未完成 rev=$(APP_REV demo-app)"
# 等待镜像拉取失败暴露
for i in $(seq 1 25); do
  BAD=$(kubectl -n demo get pods -o json 2>/dev/null | jq -r '[.items[]? | select(.status.phase=="Pending") | .status.containerStatuses[]?.state.waiting.reason] | join(",")')
  [ -n "$BAD" ] && break
  sleep 5
done
echo "    - 异常 Pod 等待原因: ${BAD:-none}"
if echo "$BAD" | grep -qE "ImagePullBackOff|ErrImagePull|ContainerCreating|CrashLoop"; then
  ok "TC-08a 新副本卡在镜像拉取" "$BAD"
else
  ng "TC-08a 新副本卡在镜像拉取" "未观察到 pull 失败，原因=[$BAD]"
fi
AVAIL=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.availableReplicas}')
READY=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}')
HB=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30081/)
assert_eq "TC-08b 旧副本仍在提供服务" "$HB" "200"
info "Deployment availableReplicas=$AVAIL readyReplicas=$READY"
HL=$(APP_HEALTH demo-app); ST=$(APP_SYNC demo-app)
info "ArgoCD 判定: sync=$ST health=$HL"
if [ "$HL" = "Healthy" ]; then
  echo "    ! 生产盲区：旧副本可用 -> ArgoCD 仍报 Healthy，滚动更新失败不会体现为 Degraded，需配合镜像预检/告警"
else
  ok "TC-08c ArgoCD 感知异常" "health=$HL"
fi
echo "    - 恢复: 还原镜像 tag"
git -C $REPO_DIR checkout -q "$BASE" -- .
cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "tc08 restore" >/dev/null 2>&1 && git push -q origin main 2>&1 | tail -1
wait_rev demo-app "$(git rev-parse HEAD)" 60 >/dev/null
if wait_health demo-app Healthy 120; then ok "TC-08d 回滚后恢复健康" "Healthy"; else ng "TC-08d 回滚后恢复健康" "$(APP_HEALTH demo-app)"; fi
kubectl -n demo get pods --no-headers | awk '{print $3}' | sort | uniq -c
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
