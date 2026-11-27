#!/bin/bash
set -uo pipefail
BK=$(cat /tmp/exturl-backup-dir)
echo "===== 1. 改 /etc/gitlab/gitlab.rb ====="
python3 - <<'PY'
p="/etc/gitlab/gitlab.rb"
s=open(p).read()
assert "external_url 'http://192.168.200.12'" in s
s=s.replace("external_url 'http://192.168.200.12'",
"""external_url 'https://gitlab.corp.local'
## 反向代理在网关终结 TLS，本机 nginx 只监听 80 明文
nginx['listen_port'] = 80
nginx['listen_https'] = false
letsencrypt['enable'] = false
gitlab_rails['trusted_proxies'] = ['192.168.200.0/24', '10.96.0.0/12', '10.244.0.0/16']""")

# omniauth：issuer / 端点 / scheme host port
s=s.replace('issuer: "http://192.168.200.12:30087/realms/corp"',
            'issuer: "https://keycloak.corp.local/realms/corp"')
s=s.replace('scheme: "http",\n        host: "192.168.200.12",\n        port: 30087,',
            'scheme: "https",\n        host: "keycloak.corp.local",\n        port: 443,')
s=s.replace('http://192.168.200.12:30087/realms/corp/protocol/openid-connect',
            'https://keycloak.corp.local/realms/corp/protocol/openid-connect')
s=s.replace('redirect_uri: "http://192.168.200.12/users/auth/openid_connect/callback"',
            'redirect_uri: "https://gitlab.corp.local/users/auth/openid_connect/callback"')
open(p,"w").write(s)
PY
echo "--- 改动结果 ---"
grep -nE "external_url|listen_port|listen_https|trusted_proxies|issuer:|scheme:|host: \"|port:|redirect_uri|_endpoint:|jwks_uri" /etc/gitlab/gitlab.rb | head -20
git config --global --add safe.directory /etc/gitlab 2>/dev/null || true

echo "===== 2. 语法检查 ====="
ruby -c /etc/gitlab/gitlab.rb

echo "===== 3. reconfigure（3-5 分钟） ====="
gitlab-ctl reconfigure 2>&1 | tail -8
