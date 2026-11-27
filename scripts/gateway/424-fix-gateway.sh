#!/bin/bash
set -uo pipefail
VIP=192.168.200.210
echo "=== 宿主 8090 自测 ==="
curl -s -o /dev/null -w '  host_8090=%{http_code}\n' http://192.168.200.12:8090/ || true
ss -ltn | grep 8090 || echo "  宿主 8090 未监听（podman 端口转发异常？）"
podman inspect phpldapadmin --format '{{.State.Status}} {{json .HostConfig.PortBindings}} {{.NetworkSettings.Networks}}' 2>/dev/null | head -2

echo "=== gitlab 登录页经 https ==="
curl -s -k -o /dev/null -w '  gitlab /users/sign_in=%{http_code}\n' --resolve gitlab.corp.local:443:$VIP https://gitlab.corp.local/users/sign_in
echo "=== jenkins 登录页经 https ==="
curl -s -k -o /dev/null -w '  jenkins /login=%{http_code}\n' --resolve jenkins.corp.local:443:$VIP https://jenkins.corp.local/login

echo "=== nginx fd 限制修正（worker_rlimit_nofile）+ 重载 ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' > /tmp/nginx.conf
python3 - <<'PY'
p='/tmp/nginx.conf'
s=open(p).read()
s=s.replace('worker_processes  auto;','worker_processes  auto;\nworker_rlimit_nofile 4096;',1)
s=s.replace('worker_connections  2048;','worker_connections  4096;',1)
open(p,'w').write(s)
PY
grep -n 'worker_rlimit_nofile\|worker_connections' /tmp/nginx.conf
kubectl -n gateway create configmap gateway-nginx-conf --from-file=nginx.conf=/tmp/nginx.conf \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null && echo "  CM 已更新"
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=120s
kubectl -n gateway logs deploy/gateway --tail=5 | grep -E 'warn|error|ready' || echo "  无 warn/error"
