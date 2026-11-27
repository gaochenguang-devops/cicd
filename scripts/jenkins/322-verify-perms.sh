#!/usr/bin/env bash
set -u
BASE=http://127.0.0.1:30088

login() {
  u=$1; p=$2; jar=/tmp/perm_$u.txt
  rm -f "$jar" /tmp/p_$u.html
  curl -s -c "$jar" -o /tmp/p_$u.html "$BASE/login"
  CRUMB=$(python3 - "$u" <<'PY'
import re,sys
h=open(f'/tmp/p_{sys.argv[1]}.html',encoding='utf-8',errors='ignore').read()
m=re.search(r'name="Jenkins-Crumb"[^>]*value="([^"]+)"',h)
print(m.group(1) if m else "")
PY
)
  curl -s -b "$jar" -c "$jar" -o /dev/null \
    --data-urlencode "j_username=$u" --data-urlencode "j_password=$p" \
    --data-urlencode "Jenkins-Crumb=$CRUMB" --data "from=/&Submit=Sign+in" "$BASE/j_spring_security_check"
  echo "  $u: whoAmI=$(curl -s -b "$jar" "$BASE/whoAmI/api/json" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["name"],d["authorities"][:3])' 2>/dev/null)"
  echo "     /manage -> $(curl -s -b "$jar" -o /dev/null -w '%{http_code}' "$BASE/manage")    /api/json -> $(curl -s -b "$jar" -o /dev/null -w '%{http_code}' "$BASE/api/json")"
}

echo "== 匿名 =="
echo "  / -> $(curl -s -o /dev/null -w '%{http_code}' "$BASE/")   /login -> $(curl -s -o /dev/null -w '%{http_code}' "$BASE/login")"
echo "== 登录用户权限 =="
login lead01 '__LDAP_USER_INIT_PASS__'
login dev01 '__LDAP_USER_INIT_PASS__'
login ops01 '__LDAP_USER_INIT_PASS__'
echo "== 服务入口 =="
curl -s -o /dev/null -w '  NodePort 30088 -> %{http_code}\n' http://192.168.200.12:30088/login
