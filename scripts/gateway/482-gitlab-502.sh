#!/bin/bash
set -uo pipefail
echo "=== 80/443 监听 ==="
ss -ltnp 2>/dev/null | grep -E ':80 |:443 ' | head -6
echo "=== gitlab-ctl status（摘要） ==="
gitlab-ctl status 2>&1 | awk '{print $1,$2,$3}' | head -20
echo "=== 宿主机直连 80 ==="
curl -s -o /dev/null -w "  http://127.0.0.1:80 -> %{http_code}\n" http://127.0.0.1:80/ -m 10
curl -sk -o /dev/null -w "  https://127.0.0.1:443 -> %{http_code}\n" https://127.0.0.1:443/ -m 10
echo "=== omnibus nginx 配置里的 listen ==="
grep -rn "listen \*\?:" /var/opt/gitlab/nginx/conf/gitlab-http.conf 2>/dev/null | head -4
echo "=== gitlab nginx error log 尾部 ==="
tail -5 /var/log/gitlab/nginx/gitlab_error.log 2>/dev/null
