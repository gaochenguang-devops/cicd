#!/bin/bash
set -uo pipefail
TOK="PRIVATE-TOKEN: __GITLAB_PAT__"
echo "=== pipeline 30 的 jobs ==="
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/30/jobs" | python3 -c '
import json,sys
d=json.load(sys.stdin)
if isinstance(d,dict): print(d); raise SystemExit
for j in d:
    print("  id=%s %-22s %s" % (j["id"], j["name"], j["status"]))
    if j["status"]=="failed": open("/tmp/badjob","w").write(str(j["id"]))
'
B=$(cat /tmp/badjob 2>/dev/null || true)
echo "=== 失败 job($B) 日志尾部 ==="
[ -n "$B" ] && curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/jobs/$B/trace" | tail -35
