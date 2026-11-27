#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. 依赖检查 ====="
for c in ldapsearch jq curl; do command -v $c >/dev/null && echo "  $c ok" || echo "  $c MISSING"; done

echo
echo "===== 2. 安装脚本 ====="
chmod 755 /usr/local/bin/ldap-gitlab-sync.sh
touch /var/log/ldap-gitlab-sync.log
echo "  /usr/local/bin/ldap-gitlab-sync.sh $(wc -l < /usr/local/bin/ldap-gitlab-sync.sh) 行"

echo
echo "===== 3. systemd service + timer ====="
cat > /etc/systemd/system/ldap-gitlab-sync.service <<'EOF'
[Unit]
Description=Sync LDAP groups to GitLab groups (CE self-built)
After=network-online.target gitlab-runsvdir.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ldap-gitlab-sync.sh
TimeoutStartSec=300
Nice=10
EOF

cat > /etc/systemd/system/ldap-gitlab-sync.timer <<'EOF'
[Unit]
Description=Run LDAP -> GitLab group sync every 10 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=10min
AccuracySec=30s
Unit=ldap-gitlab-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ldap-gitlab-sync.timer >/dev/null 2>&1
systemctl is-enabled ldap-gitlab-sync.timer | sed 's/^/  enabled=/'
systemctl list-timers ldap-gitlab-sync.timer --no-pager 2>/dev/null | sed -n '2p' | sed 's/^/  next: /'

echo
echo "===== 4. dry-run 首跑 ====="
/usr/local/bin/ldap-gitlab-sync.sh --dry-run 2>&1 | tail -25 | sed 's/^/  /'
