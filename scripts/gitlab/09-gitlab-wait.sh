#!/usr/bin/env bash
echo "=== 等待 reconfigure 结束 ==="
for i in $(seq 1 90); do
  if grep -q "RECONFIGURE_EXIT" /root/gitlab-reconfigure.log 2>/dev/null; then
    echo "reconfigure finished: $(grep RECONFIGURE_EXIT /root/gitlab-reconfigure.log)"
    break
  fi
  echo "[$((i*10))s] tail: $(tail -1 /root/gitlab-reconfigure.log | cut -c1-100)"
  sleep 10
done

echo "=== 等待 Web 就绪 ==="
for i in $(seq 1 60); do
  code=$(curl -sS -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1/users/sign_in 2>/dev/null)
  echo "[$((i*5))s] http=$code mem=$(free -m | awk '/Mem:/{print $3"/"$2}')MB"
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then break; fi
  sleep 5
done

echo "=== 服务状态 ==="
gitlab-ctl status 2>&1 | head -30
echo "=== 初始 root 密码 ==="
cat /etc/gitlab/initial_root_password 2>/dev/null | grep -E "Password" || echo "no initial password file"
echo "=== 端口 ==="
ss -lntp | grep -E ':80 |:2424 ' || true
echo "=== 内存 ==="
free -m | head -3
