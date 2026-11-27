#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
conds() { APP_FIELD demo-app '.status.conditions[]?.message' | head -c 320 | tr '\n' ' '; }
restart_repo() { kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server >/dev/null 2>&1; kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=150s >/dev/null 2>&1; }
annotate_and_wait() { refresh demo-app; sleep 22; }

PWB64=$(kubectl -n argocd get secret gitlab-repo-creds -o jsonpath='{.data.password}')

echo "---------------- TC-11 错误凭据（清缓存 + 注解刷新）"
kubectl -n argocd patch secret gitlab-repo-creds --type=merge \
  -p "{\"data\":{\"password\":\"$(printf 'wrong-pass-123' | base64 -w0)\"}}" >/dev/null
restart_repo; annotate_and_wait
ST=$(APP_SYNC demo-app); C=$(conds)
[ "$ST" != "Synced" ] && ok "TC-11a 错误凭据被检出" "sync=$ST msg=$(echo $C|head -c 110)" || ng "TC-11a 错误凭据被检出" "sync=$ST"
kubectl -n argocd logs deploy/argocd-repo-server --tail=80 2>/dev/null | grep -oiE "authentication failed|HTTP Basic: Access denied|authentication required" | sort -u | head -2
kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}' | grep -q 2 && ok "TC-11b 线上工作负载不受影响" "readyReplicas=2" || ng "TC-11b 线上工作负载不受影响" "$(kubectl -n demo get deploy demo-nginx -o jsonpath='{.status.readyReplicas}')"
kubectl -n argocd patch secret gitlab-repo-creds --type=merge -p "{\"data\":{\"password\":\"$PWB64\"}}" >/dev/null
restart_repo; annotate_and_wait
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-11c 恢复后自愈" "Synced/$(APP_HEALTH demo-app)" || ng "TC-11c 恢复后自愈" "$(APP_SYNC demo-app) $(conds)"
echo

echo "---------------- TC-14 PAT 轮换 / 撤销"
NJ=$(curl -s -X POST -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/users/1/personal_access_tokens?name=rotation-test&scopes[]=api&expires_at=2026-12-31")
PAT2=$(echo "$NJ" | jq -r '.token // empty'); PAT2ID=$(echo "$NJ" | jq -r '.id // empty')
[ -n "$PAT2" ] && ok "TC-14a 新建备用 PAT" "id=$PAT2ID" || ng "TC-14a 新建备用 PAT" "$(echo $NJ|head -c 100)"
kubectl -n argocd patch secret gitlab-repo-creds --type=merge \
  -p "{\"data\":{\"password\":\"$(printf '%s' "$PAT2" | base64 -w0)\"}}" >/dev/null
restart_repo; annotate_and_wait
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-14b 轮换到新 PAT 后可同步" "Synced" || ng "TC-14b 轮换到新 PAT 后可同步" "$(APP_SYNC demo-app) $(conds)"
curl -s -X DELETE -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/personal_access_tokens/$PAT2ID" -o /dev/null -w "    revoke http=%{http_code}\n"
restart_repo; annotate_and_wait
ST=$(APP_SYNC demo-app); C=$(conds)
[ "$ST" != "Synced" ] && ok "TC-14c 撤销后被检出" "sync=$ST msg=$(echo $C|head -c 100)" || ng "TC-14c 撤销后被检出" "撤销后仍 Synced（凭据仍被接受，需排查 token 撤销是否生效）"
kubectl -n argocd patch secret gitlab-repo-creds --type=merge -p "{\"data\":{\"password\":\"$PWB64\"}}" >/dev/null
restart_repo; annotate_and_wait
[ "$(APP_SYNC demo-app)" = "Synced" ] && ok "TC-14d 恢复主 PAT 自愈" "Synced/$(APP_HEALTH demo-app)" || ng "TC-14d 恢复主 PAT 自愈" "$(APP_SYNC demo-app) $(conds)"
echo

echo "================== 小结 =========="
echo "PASS=$PASS FAIL=$FAIL"
