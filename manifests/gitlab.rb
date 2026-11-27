## GitLab CE 单机配置（7G 内存优化版）—— 与服务器 /etc/gitlab/gitlab.rb 一致
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

## 备份保留 7 天
gitlab_rails['backup_keep_time'] = 604800
