#!/bin/bash
set -uo pipefail
TOK="PRIVATE-TOKEN: __GITLAB_PAT__"
for i in 1 2 3 4 5 6; do
  sleep 25
  S=$(curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/31" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')
  echo "  [$i] pipeline 31 = $S"
  [ "$S" = "success" ] || [ "$S" = "failed" ] && break
done
curl -s -H "$TOK" "http://192.168.200.12/api/v4/projects/2/pipelines/31/jobs" | python3 -c '
import json,sys
for j in json.load(sys.stdin):
    print("  %-18s %s" % (j["name"], j["status"]))
'
