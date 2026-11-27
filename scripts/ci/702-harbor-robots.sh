#!/bin/bash
H='-k --resolve harbor.corp.local:443:192.168.200.210'
echo "=== 项目级 robots ==="
for p in apps library; do
  echo "-- $p"
  curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' "https://harbor.corp.local/api/v2.0/projects/$p/robots?page=1&page_size=20" | head -c 400; echo
done
echo "=== 全局 robots（不带参数） ==="
curl -s $H -u 'admin:__HARBOR_ADMIN_PASS__' "https://harbor.corp.local/api/v2.0/robots" | head -c 400; echo
echo "=== 用 robot 登录测试（apps 项目） ==="
curl -s $H -u 'robot$apps+ci-builder:__HARBOR_ROBOT_CI_SECRET__' 'https://harbor.corp.local/service/token?service=harbor-registry&scope=repository:apps/podinfo:pull' -o /dev/null -w '  token http=%{http_code}\n'

