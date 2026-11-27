#!/bin/bash
set -uo pipefail
U='admin:__HARBOR_ADMIN_PASS__'
echo "=== Harbor 用户表（id / username / email / 创建时间 / auth 来源） ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/users?page_size=100&with_system_admin=true" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for u in sorted(d, key=lambda x:x["user_id"]):
    print(f"  id={u[\"user_id\"]:<3} {u[\"username\"]:<18} {str(u.get(\"email\")):<32} created={u.get(\"creation_time\",\"\")[:19]} admin={u.get(\"sysadmin_flag\")}")
print("  共", len(d), "个用户")
'
echo
echo "=== 与 gaochenguang 冲突的记录 ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/users?page_size=100" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for u in d:
    if "gaochenguang" in (u["username"] or "") or "gaochenguang" in (u.get("email") or ""):
        print("  id=",u["user_id"],"username=",u["username"],"email=",u.get("email"),"created=",u.get("creation_time"))
'
echo
echo "=== 当前 auth_mode 与 OIDC 配置 ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/configurations" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for k in ("auth_mode","oidc_endpoint","oidc_client_id","oidc_auto_onboard","oidc_user_claim","oidc_admin_group","oidc_groups_claim","oidc_scope"):
    print("  ",k,"=",d.get(k))
'
