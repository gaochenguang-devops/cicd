#!/usr/bin/env bash
set -uo pipefail
IMG=docker.m.daocloud.io/osixia/phpldapadmin:0.9.0

echo "===== 1. 确认镜像 ====="
podman images --format '{{.Repository}}:{{.Tag}}' | grep -i phpldapadmin | sed 's/^/  /'

echo
echo "===== 2. 写 quadlet ====="
mkdir -p /etc/containers/systemd
cat > /etc/containers/systemd/phpldapadmin.container <<'EOF'
[Unit]
Description=phpLDAPadmin (OpenLDAP Web UI)
After=network-online.target openldap.service

[Container]
Image=docker.m.daocloud.io/osixia/phpldapadmin:0.9.0
ContainerName=phpldapadmin
PublishPort=8090:80
Environment=PHPLDAPADMIN_LDAP_HOSTS=192.168.200.12
Environment=PHPLDAPADMIN_HTTPS=false
Environment=PHPLDAPADMIN_SERVER_ADMIN=admin@corp.local
Environment=PHPLDAPADMIN_SERVER_NAME_1="Corp LDAP"
Environment=PHPLDAPADMIN_LDAP_HOSTS_1_TLS=false

[Install]
WantedBy=multi-user.target
EOF
sed -i 's/^  / /' /dev/null
systemctl daemon-reload
systemctl start phpldapadmin
sleep 6

echo
echo "===== 3. 运行状态 ====="
podman ps --filter name=phpldapadmin --format '  container={{.Names}} status={{.Status}} ports={{.Ports}}'
systemctl is-active phpldapadmin | sed 's/^/  service=/'

echo
echo "===== 4. HTTP 检查 ====="
curl -s -o /tmp/pla.html -w "  http=%{http_code} size=%{size_download}\n" http://192.168.200.12:8090/
grep -oE '<title>[^<]*|phpLDAPadmin[^<]{0,20}|Corp LDAP|Login[^<]{0,10}' /tmp/pla.html | head -5 | sed 's/^/  /'

echo
echo "===== 5. 与 LDAP 连通性（容器内解析）====="
podman exec phpldapadmin sh -c 'nc -z -w3 192.168.200.12 389 && echo "  ldap_reachable=yes" || echo "  ldap_reachable=no"' 2>/dev/null || echo "  (nc 不可用，跳过)"
