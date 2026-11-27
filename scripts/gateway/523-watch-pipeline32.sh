#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
G=https://gitlab.corp.local/api/v4
for i in $(seq 1 24); do
  sleep 10
  J=$(curl -s -k -H "PRIVATE-TOKEN: $PAT" "$G/projects/2/pipelines/32")
  ST=$(echo "$J" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')
  echo "[$((i*10))s] pipeline 32: $ST"
  if [ "$ST" != "running" ] && [ "$ST" != "pending" ] && [ "$ST" != "created" ]; then break; fi
done
echo "--- 各 job ---"
curl -s -k -H "PRIVATE-TOKEN: $PAT" "$G/projects/2/pipelines/32/jobs" | python3 -c '
import sys,json
for j in json.load(sys.stdin): print("  ", j["stage"], j["name"], j["status"])
'
