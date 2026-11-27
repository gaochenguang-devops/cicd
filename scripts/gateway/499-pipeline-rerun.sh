#!/bin/bash
set -uo pipefail
echo "=== EXT_ENDPOINT 现状 ==="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
TOK="PRIVATE-TOKEN: __GITLAB_PAT__"
echo "=== 重新触发 pipeline ==="
PID=$(curl -s -X POST -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipeline" -d "ref=main" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("id",""))')
echo "  pipeline id=$PID"
sleep 50
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/$PID/jobs" | python3 -c '
import json,sys
for j in json.load(sys.stdin):
    print("  %-18s %s" % (j["name"], j["status"]))
' 2>/dev/null
sleep 40
echo "=== 再查一次 ==="
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/$PID/jobs" | python3 -c '
import json,sys
for j in json.load(sys.stdin):
    print("  %-18s %s" % (j["name"], j["status"]))
' 2>/dev/null
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/$PID" | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  overall:",d["status"],d["web_url"])'
