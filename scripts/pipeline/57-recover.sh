#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
echo "== 等待 GitLab 真正就绪（HTTP 200/302 且 puma run）=="
T0=$(date +%s); READY=no
for i in $(seq 1 50); do
  C=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://192.168.200.12/) || C=000
  P=$(gitlab-ctl status 2>/dev/null | grep -c "run: puma")
  if { [ "$C" = "200" ] || [ "$C" = "302" ]; } && [ "$P" -ge 1 ]; then READY=yes; break; fi
  sleep 5
done
echo "    - $(( $(date +%s)-T0 ))s 后 HTTP=$C puma=$P"
[ "$READY" = "yes" ] && ok "TC-19d GitLab 完全就绪" "HTTP=$C" || ng "TC-19d GitLab 完全就绪" "HTTP=$C puma=$P"
apt=$(curl -s -o /dev/null -w '%{http_code}' -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1")
echo "    - GitLab API=$apt"
refresh demo-app; sleep 20
ST=$(APP_SYNC demo-app)
[ "$ST" = "Synced" ] && ok "TC-19e ArgoCD 收敛回正常" "Synced/$(APP_HEALTH demo-app)" || ng "TC-19e ArgoCD 收敛" "$ST"
cd $REPO_DIR
git checkout -q . 2>/dev/null
sed -i -E 's/^  replicas: [0-9]+$/  replicas: 2/' deploy/deployment.yaml
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -q -m "tc19: post-restart webhook verification" >/dev/null 2>&1
git push -q origin main 2>&1 | tail -1
NEW=$(git rev-parse HEAD)
T1=$(date +%s)
if wait_rev demo-app "$NEW" 45; then ok "TC-19f 重启后 webhook 恢复" "$(( $(date +%s)-T1 ))s 内同步 ${NEW:0:7}"; else ng "TC-19f 重启后 webhook 恢复" "rev=$(APP_REV demo-app) expect=${NEW:0:7}"; fi
sleep 5
echo "    - 最终: $(APP_SYNC demo-app)/$(APP_HEALTH demo-app) replicas=$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}') pods=$(kubectl -n demo get pods --no-headers|grep -c Running)"
echo "PASS=$PASS FAIL=$FAIL"
