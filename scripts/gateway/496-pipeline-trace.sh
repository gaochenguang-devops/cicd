#!/bin/bash
set -uo pipefail
TOK="PRIVATE-TOKEN: __GITLAB_PAT__"
echo "=== 最近 pipeline 的 jobs ==="
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/28/jobs" | python3 -c '
import json,sys
for j in json.load(sys.stdin):
    print("  #%s %-22s %s" % (j["id"], j["name"], j["status"]))
    open("/tmp/job-%s.id"%j["name"].replace("/","_"),"w").write(str(j["id"]))
'
echo "=== 失败 job 的日志尾部 ==="
for f in /tmp/job-*.id; do
  ID=$(cat $f); N=$(basename $f .id)
  ST=$(curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/jobs/$ID" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')
  echo "--- $N (id=$ID status=$ST)"
done
BAD=$(for f in /tmp/job-*.id; do ID=$(cat $f); S=$(curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/jobs/$ID" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])'); [ "$S" = "failed" ] && echo $ID; done | head -1)
echo "  首个失败 job = $BAD"
[ -n "$BAD" ] && curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/jobs/$BAD/trace" | tail -30
