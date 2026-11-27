#!/bin/bash
set -uo pipefail
U='admin:__HARBOR_ADMIN_PASS__'

echo "=== 全量用户（id / username / email / 创建时间） ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/users?page_size=100" > /tmp/hu.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/hu.json"))
for u in sorted(d, key=lambda x: x["user_id"]):
    print("  id=%-3s %-20s %-34s created=%s admin=%s" % (u["user_id"], u["username"], u.get("email"), (u.get("creation_time") or "")[:19], u.get("sysadmin_flag")))
print("  共 %d 个" % len(d))
PY

echo
echo "=== gaochenguang 在各个项目里的角色（删除前先记下来） ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/projects?page_size=100" > /tmp/hp.json
python3 - <<'PY'
import json, subprocess
projs=[p["name"] for p in json.load(open("/tmp/hp.json"))]
found=[]
for p in projs:
    out=subprocess.check_output(["curl","-s","-k","-u","admin:__HARBOR_ADMIN_PASS__",
        f"https://harbor.corp.local/api/v2.0/projects/{p}/members?page_size=100"]).decode()
    try: ms=json.loads(out)
    except Exception: continue
    for m in ms:
        if m.get("entity_name")=="gaochenguang":
            found.append((p, m.get("role_name"), m.get("id")))
            print("  project=%s role=%s member_id=%s" % (p, m.get("role_name"), m.get("id")))
if not found: print("  （没有项目成员身份）")
PY

echo
echo "=== 删除冲突的本地用户 id=11 ==="
curl -s -k -u "$U" -o /dev/null -w '  DELETE user 11 -> %{http_code}\n' -X DELETE "https://harbor.corp.local/api/v2.0/users/11"

echo
echo "=== 删除后复查是否还残留 ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/users?page_size=100" | python3 -c '
import sys,json
d=json.load(sys.stdin)
hit=[u for u in d if "gaochenguang" in (u["username"] or "") or "gaochenguang" in (u.get("email") or "")]
print("  残留记录:", [(u["user_id"],u["username"],u.get("email")) for u in hit] or "无")
print("  当前用户数:", len(d))
'
