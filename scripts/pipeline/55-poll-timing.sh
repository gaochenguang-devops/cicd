#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
cd $REPO_DIR
BASE=$(cat /root/cicd-test/base.txt)
echo "== 轮询参数 =="
kubectl -n argocd get cm argocd-cmd-params-cm -o json | jq -r '.data | to_entries[] | select(.key|test("reconcil|timeout")) | "\(.key)=\(.value)"'
echo

HID=$(curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks" | jq -r '.[0].id')
curl -s -o /dev/null -X PUT -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks/$HID?push_events=false"
sed -i -E 's/^  replicas: [0-9]+$/  replicas: 4/' deploy/deployment.yaml
NEW=$(gpush "tc18b: replicas 4, no webhook")
echo "== 已推送 ${NEW:0:7}（webhook 关闭），每 10s 采样 =="
T0=$(date +%s); FIRST=""
for i in $(seq 1 24); do
  R=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}' 2>/dev/null)
  S=$(APP_SYNC demo-app)
  echo "    +$(( $(date +%s)-T0 ))s replicas=$R sync=$S rev=$(APP_REV demo-app | head -c 7)"
  if [ "$R" = "4" ] && [ -z "$FIRST" ]; then FIRST=$(( $(date +%s)-T0 )); break; fi
  sleep 10
done
if [ -n "$FIRST" ]; then
  ok "TC-18a 轮询兜底路径生效" "无 webhook 时 ${FIRST}s 完成部署（默认轮询上限 180s）"
else
  ng "TC-18a 轮询兜底路径生效" "240s 内未部署，当前 replicas=$R sync=$S"
fi
curl -s -o /dev/null -X PUT -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks/$HID?push_events=true"
git -C $REPO_DIR checkout -q "$BASE" -- .
cd $REPO_DIR && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -q -m "tc18b restore" >/dev/null 2>&1 && git push -q origin main 2>&1|tail -1
T1=$(date +%s); wait_rev demo-app "$(git rev-parse HEAD)" 45 >/dev/null; echo "    - 复位: $(APP_SYNC demo-app) replicas=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}') 用时$(( $(date +%s)-T1 ))s"
echo "PASS=$PASS FAIL=$FAIL"
