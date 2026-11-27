#!/usr/bin/env bash
# 新增 LDAP 用户：建条目 → 入组 → 立即同步到 GitLab（Harbor 重新登录即生效）
# 用法：ldap-add-user.sh <uid> <中文姓名> <组cn> [uidNumber]
# 例：  ldap-add-user.sh dev06 韩开发 developers
set -euo pipefail

uid=${1:?用法: ldap-add-user.sh <uid> <姓名> <组cn> [uidNumber]}
name=${2:?}
group=${3:?}

LDAP_HOST=192.168.200.12
BASE="dc=corp,dc=local"
ADMIN_DN="cn=admin,dc=corp,dc=local"
ADMIN_PW='__LDAP_ADMIN_PASS__'
INIT_PW='__LDAP_USER_INIT_PASS__'
L="ldapadd -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW"
M="ldapmodify -x -H ldap://$LDAP_HOST:389 -D $ADMIN_DN -w $ADMIN_PW"

case "$group" in
  devops|developers|qa|platform-admins) ;;
  *) echo "组名只能是 devops / developers / qa / platform-admins"; exit 1 ;;
esac

# uidNumber：不传则取当前最大值 +1
if [ -n "${4:-}" ]; then
  NUM=$4
else
  NUM=$(ldapsearch -x -H "ldap://$LDAP_HOST:389" -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "ou=people,$BASE" -LLL "(objectClass=posixAccount)" uidNumber 2>/dev/null \
        | awk '/^uidNumber: /{print $2}' | sort -n | tail -1)
  NUM=$(( ${NUM:-10000} + 1 ))
fi

# 1. SSHA 密码（比 phpLDAPadmin 默认的 {MD5} 强）
HASH=$(python3 - "$INIT_PW" <<'PY'
import base64, hashlib, os, sys
pw = sys.argv[1].encode(); salt = os.urandom(8)
print("{SSHA}" + base64.b64encode(hashlib.sha1(pw + salt).digest() + salt).decode())
PY
)
echo "[1/3] 密码哈希 ${HASH:0:14}..."

# 2. 建条目（DN 用 uid=，与现有 10 个账号一致）
$L >/dev/null <<EOF
dn: uid=$uid,ou=people,$BASE
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: organizationalPerson
objectClass: person
uid: $uid
cn: $name
sn: ${name:0:1}
givenName: ${name:0:1}
displayName: $name
mail: $uid@corp.local
uidNumber: $NUM
gidNumber: 10000
homeDirectory: /home/$uid
loginShell: /bin/bash
userPassword: $HASH
EOF
echo "[2/3] 已建 uid=$uid（uidNumber=$NUM）"

# 3. 入组
$M >/dev/null <<EOF
dn: cn=$group,ou=groups,$BASE
changetype: modify
add: member
member: uid=$uid,ou=people,$BASE
EOF
echo "[3/3] 已加入组 $group"

# 4. 立刻同步（不等定时器）
/usr/local/bin/ldap-gitlab-sync.sh 2>&1 | grep -E "建号成功 $uid|加组成功 $uid|结束|!!" | sed 's/^/    /'

cat <<EOF

完成。注意事项：
  - GitLab：已自动建号并赋组权限；用户从登录页 "Corp LDAP" 标签页登录即用
  - Harbor：用户访问 http://192.168.200.12:30090 重新登录，按组自动获得项目权限
  - 初始密码：$INIT_PW（务必通知本人并按需修改）
  - 改密码：见 docs/03-身份与账号\OpenLDAP目录.md 第 6 节
EOF
