#!/usr/bin/env bash
set -uo pipefail
L="ldap://192.168.200.12:389"
BASE="dc=corp,dc=local"
ADMIN="cn=admin,$BASE"
APW='__LDAP_ADMIN_PASS__'
UPW='__LDAP_USER_INIT_PASS__'
SSHA=$(slappasswd -s "$UPW")
GEN=/root/ldap-bootstrap.ldif

# 用户表：uid 姓名 邮箱 组 gid
users=(
"lead01|李平台|lead01@corp.local|platform-admins|10010"
"ops01|张运维|ops01@corp.local|devops|10011"
"ops02|王运维|ops02@corp.local|devops|10012"
"dev01|陈开发|dev01@corp.local|developers|10013"
"dev02|刘开发|dev02@corp.local|developers|10014"
"dev03|赵开发|dev03@corp.local|developers|10015"
"dev04|孙开发|dev04@corp.local|developers|10016"
"dev05|周开发|dev05@corp.local|developers|10017"
"qa01|吴测试|qa01@corp.local|qa|10018"
"qa02|郑测试|qa02@corp.local|qa|10019"
)

echo "===== 1. 生成 LDIF ====="
{
cat <<EOF
dn: ou=people,$BASE
objectClass: organizationalUnit
ou: people

dn: ou=groups,$BASE
objectClass: organizationalUnit
ou: groups
EOF

for row in "${users[@]}"; do
  IFS='|' read -r uid name mail grp gid <<< "$row"
  cat <<EOF

dn: uid=$uid,ou=people,$BASE
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: posixAccount
objectClass: top
uid: $uid
cn: $name
sn: ${name:1}
givenName: ${name:0:1}
displayName: $name
mail: $mail
uidNumber: $gid
gidNumber: $gid
homeDirectory: /home/$uid
loginShell: /bin/bash
userPassword: $SSHA
EOF
done

declare -A groups=(
  ["platform-admins"]="lead01"
  ["devops"]="ops01 ops02"
  ["developers"]="dev01 dev02 dev03 dev04 dev05"
  ["qa"]="qa01 qa02"
)
declare -A descr=(
  ["platform-admins"]="平台管理员组"
  ["devops"]="运维组"
  ["developers"]="开发组"
  ["qa"]="测试组"
)
for g in platform-admins devops developers qa; do
cat <<EOF

dn: cn=$g,ou=groups,$BASE
objectClass: groupOfNames
cn: $g
description: ${descr[$g]}
EOF
  for u in ${groups[$g]}; do
    echo "member: uid=$u,ou=people,$BASE"
  done
done
} > "$GEN"
echo "  文件行数: $(wc -l < "$GEN")"

echo
echo "===== 2. 导入 ====="
ldapadd -x -H "$L" -D "$ADMIN" -w "$APW" -f "$GEN" 2>&1 | tail -20 | sed 's/^/  /'

echo
echo "===== 3. 目录树 ====="
ldapsearch -x -H "$L" -D "$ADMIN" -w "$APW" -b "$BASE" "(objectClass=*)" dn 2>/dev/null | grep '^dn:' | sed 's/^/  /'

echo
echo "===== 4. 组成员核对 ====="
for g in platform-admins devops developers qa; do
  printf "  %-16s " "$g"
  ldapsearch -x -H "$L" -D "$ADMIN" -w "$APW" -b "cn=$g,ou=groups,$BASE" "(objectClass=groupOfNames)" member 2>/dev/null \
    | grep '^member:' | sed 's/member: uid=//; s/,ou=people.*//' | paste -sd, -
done

echo
echo "===== 5. 普通用户绑定测试（模拟应用认证）====="
for u in lead01 ops01 dev01 qa01; do
  printf "  %-8s " "$u"
  ldapwhoami -x -H "$L" -D "uid=$u,ou=people,$BASE" -w "$UPW" 2>&1 | sed 's/dn:uid=/dn:/'
done

echo
echo "===== 6. 错误密码应被拒绝 ====="
printf "  dev01 错密码: "
ldapwhoami -x -H "$L" -D "uid=dev01,ou=people,$BASE" -w 'wrongpass' 2>&1 | tail -1
