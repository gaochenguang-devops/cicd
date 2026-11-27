#!/usr/bin/env bash
# 建权限组（groupOfNames，LDAP 侧唯一被 GitLab 同步 / Harbor 继承 / ArgoCD RBAC 认的组类型）
# 用法：ldap-add-group.sh <组名cn> [说明] [首个成员uid或DN]
set -euo pipefail

cn=${1:?用法: ldap-add-group.sh <组名cn> [说明] [首个成员uid或DN]}
desc=${2:-"permission group"}
who=${3:-}

LDAP_HOST=192.168.200.12
BASE="dc=corp,dc=local"
ADMIN_DN="cn=admin,dc=corp,dc=local"
ADMIN_PW='__LDAP_ADMIN_PASS__'
Q="ldapsearch -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW -LLL"
L="ldapadd -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW"
M="ldapmodify -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW"

DN="cn=$cn,ou=groups,$BASE"

# 组名只允许小写字母、数字、点、横线、下划线（三套系统都按这个值匹配）
if ! [[ "$cn" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "组名只能用 小写字母/数字/.-_ ，且不以符号开头：$cn" >&2; exit 1
fi

# 已存在则直接报错退出
if $Q -b "$BASE" "(cn=$cn)" dn 2>/dev/null | grep -q '^dn:'; then
  echo "组 $cn 已存在：$DN" >&2; exit 1
fi

# groupOfNames 必须至少有一个 member，否则 schema 直接拒绝
if [ -z "$who" ]; then
  echo "groupOfNames 必须带至少一个 member。" >&2
  echo "用法：ldap-add-group.sh $cn '说明' dev01" >&2
  echo "（可以先拉一个现有成员进组，建好后再增删）" >&2
  exit 1
fi

# 成员可以是 uid，也可以是完整 DN
case "$who" in
  *",dc=corp,dc=local") MDN="$who" ;;
  *) MDN=$($Q -b "ou=people,$BASE" "(uid=$who)" 2>/dev/null | python3 -c '
import sys, base64
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("dn:: "):
        print(base64.b64decode(line[5:].strip()).decode()); break
    if line.startswith("dn: "):
        print(line[4:]); break
')
     [ -n "${MDN:-}" ] || { echo "找不到 uid=$who（也不像完整 DN）" >&2; exit 1; }
     ;;
esac

echo "[1/2] 建组 $DN（成员：$MDN）"
$L >/dev/null <<EOF
dn: $DN
objectClass: groupOfNames
objectClass: top
cn: $cn
description: $desc
member: $MDN
EOF

echo "[2/2] 读回"
$Q -b "$DN" cn description member 2>/dev/null | grep -vE '^#|^$|^dn' | sed 's/^/    /'

cat <<EOF

注意：新建的组在 LDAP 里已经生效（Harbor/GitLab/ArgoCD 登录时会读到），
但它默认没有任何系统权限，要按需在三处登记（详见 docs/03-身份与账号\LDAP新增用户手册.md 第 9 节）：
  - GitLab：/usr/local/bin/ldap-gitlab-sync.sh 顶部 GMAP 加 "组名:GitLab组id:角色级别"，否则不建 GitLab 组
  - Harbor：Harbor 项目 → 成员 → 添加组成员（组名填 $cn）
  - ArgoCD：argocd-rbac-cm 的 policy.csv 加 "g, $cn, role:readonly"（要管理员就 role:admin）
EOF
