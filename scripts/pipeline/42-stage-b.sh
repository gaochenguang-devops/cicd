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
  sleep 4
}

echo "---------------- TC-06 镜像版本变更：应触发滚动更新且服务不中断"
sed -i 's#nginx:1.27-alpine#nginx:1.26-alpine#' deploy/deployment.yaml
NEW=$(gpush "tc06: image 1.27 -> 1.26")
T0=$(date +%s)
if wait_rev demo-app "$NEW" 45; then ok "TC-06a 变更已同步" "$(( $(date +%s)-T0 ))s"; else ng "TC-06a 变更已同步" "rev=$(APP_REV demo-app)"; fi
OKIMG=no
for i in $(seq 1 30); do
  IMG=$(kubectl -n demo get pods -l app=demo-nginx -o jsonpath='{.items[*].spec.containers[0].image}' 2>/dev/null)
  echo "$IMG" | grep -q '1.26-alpine' && { OKIMG=yes; break; }
  sleep 4
done
[ "$OKIMG" = "yes" ] && ok "TC-06b Pod 镜像已更新" "$IMG" || ng "TC-06b Pod 镜像已更新" "$IMG"
if wait_health demo-app Healthy 90; then ok "TC-06c 更新后健康" "Healthy"; else ng "TC-06c 更新后健康" "$(APP_HEALTH demo-app)"; fi
HB=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:30081/)
assert_eq "TC-06d 服务可访问" "$HB" "200"
reset_repo
wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null
wait_health demo-app Healthy 90 >/dev/null
echo

echo "---------------- TC-07 增量资源：新增 ConfigMap 上线，删除后应被 prune"
cat > deploy/configmap.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-config
  labels:
    app: demo-nginx
    managed-by: argocd
data:
  APP_ENV: "test"
  LOG_LEVEL: "info"
YAML
sed -i 's#^  - service.yaml#  - service.yaml\n  - configmap.yaml#' deploy/kustomization.yaml
NEW=$(gpush "tc07: add configmap")
wait_rev demo-app "$NEW" 45 && ok "TC-07a 新增资源已同步" "rev=${NEW:0:7}" || ng "TC-07a 新增资源已同步" "rev=$(APP_REV demo-app)"
sleep 4
CM=$(kubectl -n demo get cm demo-config -o jsonpath='{.data.APP_ENV}' 2>/dev/null)
[ "$CM" = "test" ] && ok "TC-07b 集群中已创建 ConfigMap" "APP_ENV=$CM" || ng "TC-07b 集群中已创建 ConfigMap" "APP_ENV=[$CM]"
# 删除
git rm -q deploy/configmap.yaml
sed -i '/- configmap.yaml/d' deploy/kustomization.yaml
NEW=$(gpush "tc07: remove configmap")
wait_rev demo-app "$NEW" 45 >/dev/null
sleep 5
kubectl -n demo get cm demo-config >/dev/null 2>&1 && ng "TC-07c ConfigMap 被 prune" "仍存在" || ok "TC-07c ConfigMap 被 prune" "已回收"
reset_repo
wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
