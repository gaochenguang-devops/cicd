#!/usr/bin/env bash
# LDAP → GitLab 组同步（GitLab CE 自建，等价于 EE 的 ldap_group_sync）
#
# 做的事：
#   1. 读 LDAP 的 4 个组（devops/developers/qa/platform-admins）成员
#   2. GitLab 里没有的账号 → 用 API 自动建号（provider=ldapmain + extern_uid=DN）
#   3. 组内缺人 → 补齐（access_level 由映射表决定）
#   4. 组内多了人（仅限 LDAP 账号，特指 root 等本地账号永不处理）→ 移除
#   5. platform-admins 成员 → 设为 GitLab 实例管理员（只升不降，降权需人工）
#
# 用法：ldap-gitlab-sync.sh [--dry-run]
set -uo pipefail

GL="${GL:-http://192.168.200.12}"
TOK="${GL_TOKEN:-__GITLAB_PAT__}"
LDAP_HOST="${LDAP_HOST:-192.168.200.12}"
BASE="dc=corp,dc=local"
ADMIN_DN="cn=admin,dc=corp,dc=local"
ADMIN_PW="${LDAP_ADMIN_PW:-__LDAP_ADMIN_PASS__}"
INIT_PW="${LDAP_USER_PW:-__LDAP_USER_INIT_PASS__}"
LOG="${LOG:-/var/log/ldap-gitlab-sync.log}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
# 默认移除"已退出 LDAP 组"的成员；设 REMOVE_STALE=0 可只加不删
REMOVE_STALE="${REMOVE_STALE:-1}"

# LDAP 组 cn → GitLab 组 id:access_level（50=owner 40=maintainer 30=developer 20=reporter）
declare -A GMAP=([devops]="5:40" [developers]="6:30" [qa]="7:20")
ADMIN_GROUP="platform-admins"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
CREATED=0; ADDED=0; REMOVED=0; ADMINS=0; ERRORS=0

log() { echo "[$(date '+%F %T')] $*" >&2; echo "[$(date '+%F %T')] $*" >> "$LOG"; }
ld()  { ldapsearch -x -H "ldap://$LDAP_HOST:389" -D "$ADMIN_DN" -w "$ADMIN_PW" -LLL "$@" 2>/dev/null; }

# ---------- 1. GitLab 现有用户 ----------
fetch_gl_users() {
  : > "$WORK/users.jsonl"
  local page=1
  while [ "$page" -le 10 ]; do
    local body n
    body=$(curl -s --max-time 20 -H "PRIVATE-TOKEN: $TOK" \
      "$GL/api/v4/users?per_page=100&page=$page")
    n=$(echo "$body" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo 0)
    [ "$n" -eq 0 ] && break
    echo "$body" | jq -c '.[]' >> "$WORK/users.jsonl"
    [ "$n" -lt 100 ] && break
    page=$((page+1))
  done
  jq -s '.' "$WORK/users.jsonl" > "$WORK/users_all.json" 2>/dev/null || echo '[]' > "$WORK/users_all.json"
  jq 'length' "$WORK/users_all.json"
}

uid_to_id()  { jq -r --arg u "$1" '.[] | select(.username==$u) | .id' "$WORK/users_all.json" 2>/dev/null | head -1; }

ldap_user_list() { ld -b "ou=people,$BASE" "(objectClass=inetOrgPerson)" uid | awk '/^uid: /{print $2}'; }

dn_to_uid() { # 组里 member 的 DN → uid 属性（不依赖 DN 前缀是 uid 还是 cn）
  local dn=$1 u
  u=$(ld -b "$dn" -s base "(objectClass=*)" uid | awk '/^uid: /{print $2; exit}')
  [ -n "$u" ] && { echo "$u"; return; }
  echo "$dn" | sed -nE 's/^uid=([^,]+),.*/\1/p'
}

ld_members() { # 组 cn → 每行一个 member DN（中文 DN 会被 LDIF 编成 base64：member:: xxx）
  ld -b "cn=$1,ou=groups,$BASE" "(objectClass=groupOfNames)" member | python3 -c '
import sys, base64
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("member:: "):
        print(base64.b64decode(line[len("member:: "):]).decode("utf-8", "ignore"))
    elif line.startswith("member: "):
        print(line[len("member: "):])
'
}

dn_of() { # 过滤器 → 第一个命中条目的真实 DN；含中文时 LDAP 会输出 base64 的 dn:: xxx
  ld -b "ou=people,$BASE" "($1)" | python3 -c '
import sys, base64
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("dn:: "):
        print(base64.b64decode(line[len("dn:: "):]).decode("utf-8", "ignore")); break
    if line.startswith("dn: "):
        print(line[len("dn: "):]); break
'
}

uid_to_dn() { # uid → 真实 DN（兼容 cn=姓名,... 这类网页建出来的条目）
  local d; d=$(dn_of "uid=$1")
  echo "${d:-uid=$1,ou=people,$BASE}"
}

user_meta() { # uid → "cn\tmail"，注意中文属性 LDAP 会返回 base64（cn:: xxx）
  ld -b "ou=people,$BASE" "(uid=$1)" cn mail | python3 -c '
import sys, base64
cn = mail = ""
for line in sys.stdin:
    line = line.rstrip("\n")
    for key, box in (("cn", "cn"), ("mail", "mail")):
        if line.startswith(key + ":: "):
            v = base64.b64decode(line[len(key) + 3:]).decode("utf-8", "ignore")
        elif line.startswith(key + ": "):
            v = line[len(key) + 2:]
        else:
            continue
        if key == "cn" and not cn: cn = v
        if key == "mail" and not mail: mail = v
print((cn or ""), (mail or ""), sep="\t")
'
}

create_user() { # uid → echo id
  local uid=$1 cn mail dn
  IFS=$'\t' read -r cn mail <<< "$(user_meta "$uid")"
  [ -z "$cn" ] && cn="$uid"
  [ -z "$mail" ] && mail="$uid@corp.local"
  # 身份用真实 DN：界面创建的条目 DN 可能是 cn=姓名,...，不能写死 uid=<uid>
  dn=$(uid_to_dn "$uid"); [ -z "$dn" ] && dn="uid=$uid,ou=people,$BASE"
  if [ "$DRY" -eq 1 ]; then log "  [dry] 建号 $uid ($cn) extern_uid=$dn"; echo ""; return; fi
  local code body
  body=$(curl -s --max-time 20 -X POST "$GL/api/v4/users" -H "PRIVATE-TOKEN: $TOK" \
    --data-urlencode "email=$mail" \
    --data-urlencode "username=$uid" \
    --data-urlencode "name=$cn" \
    --data-urlencode "password=$INIT_PW" \
    --data-urlencode "provider=ldapmain" \
    --data-urlencode "extern_uid=$dn" \
    --data-urlencode "skip_confirmation=true")
  code=$(echo "$body" | jq -r '.id // .message // "err"' 2>/dev/null)
  if [[ "$code" =~ ^[0-9]+$ ]]; then
    log "  建号成功 $uid → id=$code"
    echo "$code"
  else
    log "  !! 建号失败 $uid: $(echo "$body" | head -c 160)"
    echo ""
  fi
}

ensure_member() { # gid uid id level
  local gid=$1 uid=$2 id=$3 lvl=$4
  [ -z "$id" ] && return
  if [ "$DRY" -eq 1 ]; then log "  [dry] 加组 $uid → 组$gid (lvl=$lvl)"; return; fi
  local code
  code=$(curl -s --max-time 20 -o "$WORK/r.json" -w "%{http_code}" \
    -X POST "$GL/api/v4/groups/$gid/members" -H "PRIVATE-TOKEN: $TOK" \
    --data-urlencode "user_id=$id" --data-urlencode "access_level=$lvl")
  case "$code" in
    201) log "  加组成功 $uid → 组$gid (lvl=$lvl)"; ADDED=$((ADDED+1));;
    409|400) : ;;                      # 已存在，静默
    *) log "  !! 加组失败 $uid → 组$gid http=$code $(head -c 120 "$WORK/r.json")"; ERRORS=$((ERRORS+1));;
  esac
}

# ---------- main ----------
log "===== 同步开始（dry_run=$DRY, remove_stale=$REMOVE_STALE）====="
total=$(fetch_gl_users)
log "GitLab 现有用户 $total 个"

ldap_user_list > "$WORK/ldap_uids.txt"
log "LDAP 用户 $(wc -l < "$WORK/ldap_uids.txt" | tr -d ' ') 个"

# 平台管理员名单先取出来：他们永远不参与"清退"，避免把 lead01 从 devops 组里删掉
ld_members "$ADMIN_GROUP" > "$WORK/admin_dns.txt"
: > "$WORK/admins.txt"
while read -r dn; do
  [ -z "$dn" ] && continue
  uid=$(dn_to_uid "$dn"); [ -n "$uid" ] && echo "$uid" >> "$WORK/admins.txt"
done < "$WORK/admin_dns.txt"
sort -u -o "$WORK/admins.txt" "$WORK/admins.txt"

for cn in "${!GMAP[@]}"; do
  gid=${GMAP[$cn]%%:*}; lvl=${GMAP[$cn]##*:}
  ld_members "$cn" > "$WORK/dns_$cn.txt"
  : > "$WORK/want_$cn.txt"
  while read -r dn; do
    [ -z "$dn" ] && continue
    u=$(dn_to_uid "$dn"); [ -n "$u" ] && echo "$u" >> "$WORK/want_$cn.txt"
  done < "$WORK/dns_$cn.txt"
  sort -u -o "$WORK/want_$cn.txt" "$WORK/want_$cn.txt"
  log "组 $cn (GitLab id=$gid lvl=$lvl)：LDAP 成员 $(tr '\n' ' ' < "$WORK/want_$cn.txt")"

  # 先取 GitLab 侧当前成员，避免重复 POST，并感知角色漂移
  curl -s --max-time 20 -H "PRIVATE-TOKEN: $TOK" "$GL/api/v4/groups/$gid/members/all" \
    | jq -r '.[] | [.username, (.id|tostring), (.access_level|tostring)] | @tsv' > "$WORK/have_$cn.txt"
  : > "$WORK/have_names_$cn.txt"
  while IFS=$'\t' read -r uname uid_id cur_lvl; do
    [ -z "$uname" ] && continue
    echo "$uname" >> "$WORK/have_names_$cn.txt"
    # 角色漂移：在同一组内但等级不同 → 更新
    if grep -qx "$uname" "$WORK/want_$cn.txt" && [ "$cur_lvl" != "$lvl" ]; then
      if [ "$DRY" -eq 1 ]; then log "  [dry] 调级 $uname 组$gid $cur_lvl→$lvl"; else
        code=$(curl -s --max-time 20 -o /dev/null -w "%{http_code}" \
          -X PUT "$GL/api/v4/groups/$gid/members/$uid_id" -H "PRIVATE-TOKEN: $TOK" \
          --data-urlencode "access_level=$lvl")
        [ "$code" = "200" ] && log "  调级 $uname 组$gid $cur_lvl→$lvl" && ADDED=$((ADDED+1)) \
                            || { log "  !! 调级失败 $uname 组$gid http=$code"; ERRORS=$((ERRORS+1)); }
      fi
    fi
  done < "$WORK/have_$cn.txt"

  # 补齐：建号 + 加组（已在组内的跳过）
  while read -r uid; do
    [ -z "$uid" ] && continue
    grep -qx "$uid" "$WORK/ldap_uids.txt" || { log "  悬空成员 $uid（ou=people 无此条目），跳过"; continue; }
    grep -qx "$uid" "$WORK/have_names_$cn.txt" && continue
    id=$(uid_to_id "$uid")
    if [ -z "$id" ]; then
      id=$(create_user "$uid")
      [ -z "$id" ] && ERRORS=$((ERRORS+1)) || CREATED=$((CREATED+1))
      if [ -n "$id" ] && [ "$DRY" -eq 0 ]; then
        jq --arg u "$uid" --argjson i "$id" '. + [{username:$u,id:$i}]' \
          "$WORK/users_all.json" > "$WORK/u.tmp" && mv "$WORK/u.tmp" "$WORK/users_all.json"
      fi
    fi
    ensure_member "$gid" "$uid" "$id" "$lvl"
  done < "$WORK/want_$cn.txt"

  # 清退：只在 LDAP 账号范围内删，root 等本地账号永不涉及
  if [ "$REMOVE_STALE" = "1" ]; then
    while IFS=$'\t' read -r uname uid_id cur_lvl; do
      [ -z "$uname" ] && continue
      grep -qx "$uname" "$WORK/ldap_uids.txt" || continue       # 非 LDAP 账号跳过
      grep -qx "$uname" "$WORK/want_$cn.txt" && continue         # 该在组内
      grep -qx "$uname" "$WORK/admins.txt" && continue           # 平台管理员不清退
      if [ "$DRY" -eq 1 ]; then log "  [dry] 移除 $uname ← 组$gid"; continue; fi
      code=$(curl -s --max-time 20 -o /dev/null -w "%{http_code}" \
        -X DELETE "$GL/api/v4/groups/$gid/members/$uid_id" -H "PRIVATE-TOKEN: $TOK")
      if [ "$code" = "204" ]; then log "  移除 $uname ← 组$gid"; REMOVED=$((REMOVED+1));
      else log "  !! 移除失败 $uname ← 组$gid http=$code"; ERRORS=$((ERRORS+1)); fi
    done < "$WORK/have_$cn.txt"
  fi
done

# ---------- platform-admins → 实例管理员（名单已在上面取好）----------
while read -r uid; do
  [ -z "$uid" ] && continue
  grep -qx "$uid" "$WORK/ldap_uids.txt" || { log "  悬空管理员 $uid（ou=people 无此条目），跳过"; continue; }
  id=$(uid_to_id "$uid")
  if [ -z "$id" ]; then id=$(create_user "$uid"); [ -z "$id" ] && ERRORS=$((ERRORS+1)) || CREATED=$((CREATED+1)); fi
  [ -z "$id" ] && continue
  is_admin=$(curl -s --max-time 20 -H "PRIVATE-TOKEN: $TOK" "$GL/api/v4/users/$id" | jq -r '.is_admin // false')
  if [ "$is_admin" = "true" ]; then log "  管理员已有 $uid"; continue; fi
  if [ "$DRY" -eq 1 ]; then log "  [dry] 设管理员 $uid"; continue; fi
  code=$(curl -s --max-time 20 -o /dev/null -w "%{http_code}" -X PUT "$GL/api/v4/users/$id" \
    -H "PRIVATE-TOKEN: $TOK" --data-urlencode "admin=true")
  [ "$code" = "200" ] && { log "  设管理员 $uid"; ADMINS=$((ADMINS+1)); } \
                      || { log "  !! 设管理员失败 $uid http=$code"; ERRORS=$((ERRORS+1)); }
done < "$WORK/admins.txt"

log "===== 结束：建号 $CREATED，加组 $ADDED，移除 $REMOVED，设管理员 $ADMINS，错误 $ERRORS ====="
[ "$ERRORS" -eq 0 ] || exit 1
