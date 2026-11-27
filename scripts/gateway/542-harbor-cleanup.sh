#!/bin/bash
set -uo pipefail
U='admin:__HARBOR_ADMIN_PASS__'
echo "=== 清掉上一轮 SSO 探针留下的 Harbor 本地记录 sso-probe(id=18) ==="
curl -s -k -u "$U" -o /dev/null -w '  DELETE 18 -> %{http_code}\n' -X DELETE "https://harbor.corp.local/api/v2.0/users/18"

echo "=== dev01 的项目成员身份（潜在同类冲突，先记录不动手） ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/projects?page_size=100" > /tmp/hp2.json
python3 - <<'PY'
import json, subprocess
projs=[p["name"] for p in json.load(open("/tmp/hp2.json"))]
for p in projs:
    out=subprocess.check_output(["curl","-s","-k","-u","admin:__HARBOR_ADMIN_PASS__",
        f"https://harbor.corp.local/api/v2.0/projects/{p}/members?page_size=100"]).decode()
    try: ms=json.loads(out)
    except Exception: continue
    for m in ms:
        if m.get("entity_name") in ("dev01","gaochenguang"):
            print("  project=%s user=%s role=%s" % (p, m.get("entity_name"), m.get("role_name")))
PY

echo "=== 最终用户表 ==="
curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/users?page_size=100" > /tmp/hu2.json
python3 - <<'PY'
import json
for u in json.load(open("/tmp/hu2.json")):
    print("  id=%-3s %-16s %s" % (u["user_id"], u["username"], u.get("email")))
PY
echo "=== 再探一次 OIDC 起跳，确认配置没被动坏 ==="
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login | grep -i '^location' | sed 's/.*redirect_uri=\([^&]*\).*/  redirect_uri=\1/' | head -1
