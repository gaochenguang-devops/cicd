#!/bin/bash
set -uo pipefail
for u in https://ipinfo.io/ip https://ifconfig.me/ip https://api.ipify.org https://www.taobao.com/help/getip.php; do
  printf '%-45s ' "$u"
  curl -s -m 8 "$u" | tr -d '\n' | head -c 60
  echo
done

