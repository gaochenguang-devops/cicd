#!/usr/bin/env bash
set -uo pipefail
echo "== 安装 gitlab-runner 二进制 =="
curl -sSL -o /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
chmod +x /usr/local/bin/gitlab-runner
gitlab-runner --version | head -2
echo
echo "== 以 root 安装为系统服务（shell executor 需 root 才能用 podman 构建）=="
mkdir -p /root/gitlab-runner
if ! systemctl cat gitlab-runner >/dev/null 2>&1; then
  gitlab-runner install --user root --working-directory /root/gitlab-runner 2>&1 | tail -3
fi
mkdir -p /etc/gitlab-runner
cat > /etc/gitlab-runner/config.toml <<'EOF'
concurrency = 1
check_interval = 0
log_level = "info"

[session_server]
  session_timeout = 1800
EOF
systemctl enable gitlab-runner >/dev/null 2>&1
systemctl restart gitlab-runner
sleep 3
systemctl is-active gitlab-runner
gitlab-runner --version | head -1
echo
echo "== podman 可用性（shell executor 依赖）=="
podman version --format '{{.Client.Version}}' 2>/dev/null
podman images --format '{{.Repository}}:{{.Tag}}' | head -3
echo
echo "== 网络与 GitLab 连通 =="
curl -s -o /dev/null -w "gitlab=%{http_code}\n" http://192.168.200.12/
