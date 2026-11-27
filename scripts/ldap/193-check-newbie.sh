#!/usr/bin/env bash
set -uo pipefail
BASE="dc=corp,dc=local"
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w __LDAP_ADMIN_PASS__ \
  -b "ou=people,$BASE" -LLL "(objectClass=posixAccount)" dn uid uidNumber cn > /tmp/people.ldif
python3 - <<'PY'
import base64, re
raw = open('/tmp/people.ldif', encoding='utf-8').read().split('\n\n')
def dec(v):
    # 处理 LDIF 折行：续行以单个空格开头
    if v.startswith('::'):
        b = v[2:].strip().replace('\n ', '')
        return base64.b64decode(b).decode('utf-8')
    return v[1:].strip()
for blk in raw:
    if not blk.strip():
        continue
    kv = {}
    last = None
    for line in blk.splitlines():
        if line.startswith(' '):
            kv[last] += line[1:]
            continue
        if ':' in line:
            k, v = line.split(':', 1)
            kv[k] = v
            last = k
    dn = kv.get('dn', '')
    dn = base64.b64decode(dn[2:].strip()).decode() if dn.startswith('::') else dn[1:].strip()
    uid = kv.get('uid', '')
    uid = base64.b64decode(uid[2:].strip()).decode() if uid.startswith('::') else uid[1:].strip()
    num = kv.get('uidNumber', '').strip()
    print(f"  {uid:<14} uidNumber={num:<7} dn={dn}")
PY
echo "--- 组引用 ---"
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w __LDAP_ADMIN_PASS__ \
  -b "ou=groups,$BASE" -LLL "(objectClass=groupOfNames)" cn member | grep -E '^cn:|member' | sed 's/^/  /' | head -40
