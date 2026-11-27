#!/bin/bash
set -uo pipefail
sed -n '60,100p' /etc/gitlab/gitlab.rb
echo "########## runner config 全文（脱敏前先备份） ##########"
cp /etc/gitlab-runner/config.toml /root/exturl-backup-$(date +%Y%m%d-%H%M%S)-runner.toml 2>/dev/null
sed -n '1,40p' /etc/gitlab-runner/config.toml
echo "########## 主机 hosts 现状 ##########"
grep -n "corp.local" /etc/hosts || echo "  (无 corp.local 记录)"
