#!/usr/bin/env bash
set -uo pipefail
HARBOR=192.168.200.12:30090
ADMIN_PW='__LDAP_ADMIN_PASS__'
DOMAIN='corp.local'
BASE='dc=corp,dc=local'

echo "===== 1. 安装 LDAP 客户端工具 ====="
if ! command -v ldapsearch >/dev/null; then
  dnf install -y openldap-clients >/tmp/dnf-ldap.log 2>&1 && echo "  安装成功" || { echo "  安装失败，见 /tmp/dnf-ldap.log"; tail -5 /tmp/dnf-ldap.log; }
fi
command -v ldapsearch ldapadd slappasswd

echo
echo "===== 2. 镜像转存到 Harbor ====="
U=$(head -1 /root/harbor-ci-creds.txt); S=$(tail -1 /root/harbor-ci-creds.txt)
podman tag docker.m.daocloud.io/osixia/openldap:1.5.0 $HARBOR/apps/openldap:1.5.0
echo "$S" | podman login --tls-verify=false -u "$U" --password-stdin $HARBOR >/dev/null 2>&1
podman push --tls-verify=false -q $HARBOR/apps/openldap:1.5.0 2>&1 | tail -1
echo "  pushed"

echo
echo "===== 3. 数据目录 ====="
mkdir -p /data/openldap/data /data/openldap/config
chown -R 1001:1001 /data/openldap 2>/dev/null || true

echo
echo "===== 4. 生成 systemd quadlet ====="
cat > /etc/containers/systemd/openldap.container <<EOF
[Unit]
Description=OpenLDAP (osixia 1.5.0)
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=openldap
Image=$HARBOR/apps/openldap:1.5.0
PublishPort=389:389
Volume=/data/openldap/data:/var/lib/ldap
Volume=/data/openldap/config:/etc/ldap/slapd.d
Environment=LDAP_ORGANISATION=Corp
Environment=LDAP_DOMAIN=$DOMAIN
Environment=LDAP_ADMIN_PASSWORD=$ADMIN_PW
Environment=LDAP_CONFIG_PASSWORD=$ADMIN_PW
Environment=LDAP_REMOVE_CONFIG_AFTER_SETUP=false
Environment=LDAP_TLS=false
Environment=LDAP_LOG_LEVEL=256

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start openldap 2>&1 | tail -3
sleep 12
echo "  容器状态:"
podman ps --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -i ldap || echo "  未启动"
echo "  最近日志:"
podman logs --tail 8 openldap 2>&1 | sed 's/^/    /'

echo
echo "===== 5. 连通性验证 ====="
ldapwhoami -x -H ldap://192.168.200.12:389 -D "cn=admin,$BASE" -w "$ADMIN_PW" 2>&1 | sed 's/^/  /'
ldapsearch -x -H ldap://192.168.200.12:389 -D "cn=admin,$BASE" -w "$ADMIN_PW" -b "$BASE" "(objectClass=*)" dn 2>&1 | head -12 | sed 's/^/  /'
