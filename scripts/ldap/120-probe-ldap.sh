#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 主机基础 ====="
hostname; cat /etc/redhat-release 2>/dev/null | head -1
free -m | sed -n '2p'
df -h /data 2>/dev/null | tail -1

echo
echo "===== 2. 端口占用（389/636/30389）====="
ss -lntp 2>/dev/null | grep -E ':389|:636|:30389' || echo "  无占用"

echo
echo "===== 3. LDAP 客户端工具 ====="
for b in ldapsearch ldapadd ldappasswd ldapwhoami; do
  printf "  %-12s " "$b"; command -v $b || echo "缺失"
done

echo
echo "===== 4. 现有 LDAP 相关进程/容器 ====="
ps -ef | grep -i slapd | grep -v grep || echo "  无 slapd 进程"
podman ps -a --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null | grep -i ldap || echo "  无 ldap 容器"

echo
echo "===== 5. 镜像源可达性 ====="
for img in docker.m.daocloud.io/osixia/openldap:1.5.0 \
           docker.m.daocloud.io/bitnami/openldap:2.6 \
           docker.m.daocloud.io/osixia/phpldapadmin:0.9.0; do
  printf "  %-58s " "$img"
  timeout 100 podman pull -q "$img" >/dev/null 2>&1 && echo OK || echo FAIL
done
podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -iE "ldap" || true

echo
echo "===== 6. GitLab LDAP 现状 ====="
grep -n "ldap_servers\|ldap_enabled" /etc/gitlab/gitlab.rb 2>/dev/null | head -5 || echo "  未配置"
gitlab-ctl status 2>/dev/null | head -3

echo
echo "===== 7. Harbor 认证现状 ====="
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"principal":"admin","password":"__HARBOR_ADMIN_PASS__"}' http://192.168.200.12:30090/api/v2.0/users/login 2>/dev/null | head -c 400)
echo "  Harbor login 响应: ${TOKEN:0:60}"
curl -s -u "admin:__HARBOR_ADMIN_PASS__" http://192.168.200.12:30090/api/v2.0/configurations | jq -r '{auth_mode, ldap_url, ldap_base_dn, ldap_uid, ldap_scope, ldap_group_base_dn, ldap_group_search_filter, ldap_group_attribute_name}' 2>/dev/null || echo "  （无法读取配置）"
