#!/usr/bin/env bash
# 建组织单元（OU）：在 dc=corp,dc=local 下或指定父 OU 下建 ou
# 用法：ldap-add-ou.sh <ou名> [说明] [父DN，默认 dc=corp,dc=local]
set -euo pipefail

ou=${1:?用法: ldap-add-ou.sh <ou名> [说明] [父DN]}
desc=${2:-"organizational unit"}
parent=${3:-"dc=corp,dc=local"}

LDAP_HOST=192.168.200.12
ADMIN_DN="cn=admin,dc=corp,dc=local"
ADMIN_PW='__LDAP_ADMIN_PASS__'
Q="ldapsearch -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW -LLL"
L="ldapadd -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW"

if ! [[ "$ou" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "OU 名只能用 小写字母/数字/.-_ ：$ou" >&2; exit 1
fi

DN="ou=$ou,$parent"

if $Q -b "$parent" "(ou=$ou)" dn 2>/dev/null | grep -q '^dn'; then
  echo "OU 已存在：$DN" >&2; exit 1
fi

echo "[1/2] 建 $DN"
$L >/dev/null <<EOF
dn: $DN
objectClass: organizationalUnit
objectClass: top
ou: $ou
description: $desc
EOF

echo "[2/2] 读回"
$Q -b "$DN" ou description 2>/dev/null | grep -vE '^#|^$|^dn' | sed 's/^/    /'

cat <<'EOF'

注意：
  - GitLab/Harbor 的搜索基是 dc=corp,dc=local，放进新 OU 的人能被它们搜到，但
    Harbor 的组基固定为 ou=groups，GitLab 的组同步脚本也只读 ou=groups 下的四个组；
  - ArgoCD(Dex) 的用户搜索基写死为 ou=people，新 OU 里的人登录 ArgoCD 会失败，
    要用需同步改 dex.config 的 userSearch.baseDN；
  - 建议：新 OU 只用来做分区（如 ou=contractors），权限仍把人放回 ou=groups 的组里。
EOF
