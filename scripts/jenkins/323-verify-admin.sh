#!/usr/bin/env bash
set -u
BASE=http://127.0.0.1:30088
chk() {
  u=$1; jar=/tmp/perm_$u.txt
  echo "  $u: /manage/=$(curl -s -b $jar -o /dev/null -w '%{http_code}' "$BASE/manage/") \
/computer/=$(curl -s -b $jar -o /dev/null -w '%{http_code}' "$BASE/computer/") \
/script=$(curl -s -b $jar -o /dev/null -w '%{http_code}' "$BASE/script")"
}
echo "== 管理页 =="
chk lead01
chk dev01
chk ops01
echo "== 匿名 =="
echo "  /manage/=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/manage/")"
