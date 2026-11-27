#!/usr/bin/env bash
# 公共测试库：ArgoCD API 封装 / Git 提交推送 / 等待断言
export KUBECONFIG=/root/.kube/config
API="http://192.168.200.12:30080"
REPO_DIR=/root/work/cicd-demo
GL="http://192.168.200.12"
GL_TOKEN="__GITLAB_PAT__"
RESULT_DIR=/root/cicd-test
mkdir -p "$RESULT_DIR"

TOKEN=""
get_token() {
  local pw; pw=$(cat /root/.argocd-admin-password)
  TOKEN=$(curl -sk -X POST "$API/api/v1/session" -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"$pw\"}" | jq -r '.token // empty')
  [ -n "$TOKEN" ] || { echo "FATAL: argocd login failed"; exit 1; }
}

api_get()  { curl -sk -H "Authorization: Bearer $TOKEN" "$API$1"; }
api_post() { curl -sk -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "${2:-{\}}" "$API$1"; }
api_put()  { curl -sk -X PUT  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2" "$API$1"; }
refresh()  { kubectl -n argocd annotate application "$1" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1; }
sync_app() { api_post "/api/v1/applications/$1/sync" '{"prune":true}' >/dev/null 2>&1; }

APP_FIELD() { api_get "/api/v1/applications/$1" | jq -r "$2"; }
APP_REV()   { APP_FIELD "$1" '.status.sync.revision // ""'; }
APP_SYNC()  { APP_FIELD "$1" '.status.sync.status // "Unknown"'; }
APP_HEALTH(){ APP_FIELD "$1" '.status.health.status // "Unknown"'; }

# wait_rev app expect_rev timeout_sec
wait_rev() {
  local app=$1 exp=${2:0:7} lim=${3:-90} i r
  for ((i=0;i<lim/3;i++)); do
    r=$(APP_REV "$app"); [ "${r:0:7}" = "$exp" ] && return 0; sleep 3
  done
  return 1
}
wait_health() {
  local app=$1 exp=$2 lim=${3:-90} i h
  for ((i=0;i<lim/3;i++)); do
    h=$(APP_HEALTH "$app"); [ "$h" = "$exp" ] && return 0; sleep 3
  done
  return 1
}

gpush() { # gpush "msg"  -> 输出新 commit sha
  cd "$REPO_DIR" || return 1
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -q -m "$1" >/dev/null 2>&1
  git push -q origin main 2>&1 | tail -2
  git rev-parse HEAD
}
grevert() { cd "$REPO_DIR" && git reset --hard "$1" >/dev/null 2>&1 && git push -f -q origin main 2>&1 | tail -1; }

PASS=0; FAIL=0; REPORT="$RESULT_DIR/report.txt"
: > "$REPORT"
ok()   { PASS=$((PASS+1)); echo "PASS | $1 | $2" | tee -a "$REPORT"; }
ng()   { FAIL=$((FAIL+1)); echo "FAIL | $1 | $2" | tee -a "$REPORT"; }
info() { echo "    - $*"; }

# 断言辅助
assert_eq() { [ "$2" = "$3" ] && ok "$1" "期望[$3] 实际[$2]" || ng "$1" "期望[$3] 实际[$2]"; }
assert_contains() { echo "$2" | grep -q "$3" && ok "$1" "包含[$3]" || ng "$1" "未包含[$3]，实际:$(echo "$2"|head -c 200)"; }
