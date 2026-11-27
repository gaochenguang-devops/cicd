#!/usr/bin/env bash
# 08-gitlab-rpm.sh 安装 GitLab CE 19.6.1 (el10) 原生包
set -uo pipefail
RPM=gitlab-ce-19.6.1-ce.0.el10.x86_64.rpm
URL=https://packages.gitlab.com/gitlab/gitlab-ce/packages/el/10/$RPM/download.rpm

echo "=== 确认 80/2424 端口空闲 ==="
ss -lntp | grep -E ':80 |:2424 ' || echo "ports free"

echo "=== 下载 RPM ==="
cd /root
if [ ! -f $RPM ]; then
  curl -sSL --retry 3 -m 900 -o $RPM "$URL" -w "download_speed=%{speed_download}\n"
fi
ls -lh $RPM

echo "=== 安装（dnf 自动解析依赖）==="
dnf install -y /root/$RPM 2>&1 | tail -20
rpm -q gitlab-ce

echo "=== 备份并写入优化后的 gitlab.rb ==="
TS=$(date +%s)
[ -f /etc/gitlab/gitlab.rb ] && cp -a /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.bak.$TS
cat >/etc/gitlab/gitlab.rb <<'EOF'
## GitLab CE 单机配置（7G 内存优化版）
external_url 'http://192.168.200.12'
gitlab_rails['gitlab_shell_ssh_port'] = 2424
gitlab_rails['time_zone'] = 'Asia/Shanghai'

## 关闭非必需组件，节省内存
prometheus_monitoring['enable'] = false
node_exporter['enable'] = false
gitlab_exporter['enable'] = false
redis_exporter['enable'] = false
postgres_exporter['enable'] = false
gitlab_kas['enable'] = false
gitlab_pages['enable'] = false
registry['enable'] = false
mattermost['enable'] = false

## 应用服务内存控制
puma['worker_processes'] = 2
puma['min_threads'] = 1
puma['max_threads'] = 4
sidekiq['max_concurrency'] = 5
postgresql['shared_buffers'] = '256MB'
postgresql['max_worker_processes'] = 6
redis['maxmemory'] = '256mb'
redis['maxmemory_policy'] = 'allkeys-lru'

## 备份保留
gitlab_rails['backup_keep_time'] = 604800
EOF
echo "--- gitlab.rb 关键项 ---"
grep -vE '^\s*#|^\s*$' /etc/gitlab/gitlab.rb

echo "=== 后台执行 reconfigure（约 5-15 分钟）==="
nohup bash -c "gitlab-ctl reconfigure > /root/gitlab-reconfigure.log 2>&1; echo RECONFIGURE_EXIT=\$? >> /root/gitlab-reconfigure.log" >/dev/null 2>&1 &
sleep 20
tail -5 /root/gitlab-reconfigure.log
echo "=== RPM INSTALL DONE (reconfigure running) ==="
