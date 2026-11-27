#!/bin/bash
PAT=__GITLAB_PAT__
curl -s -H "PRIVATE-TOKEN: $PAT" 'http://192.168.200.12/api/v4/users?per_page=100' \
 | python3 -c 'import sys,json;d=json.load(sys.stdin);print("count=",len(d));print([u["username"] for u in d])'
echo "== harbor project members =="
curl -s -u admin:'__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/apps/members' \
 | python3 -c 'import sys,json;d=json.load(sys.stdin);print([(m["entity_name"],m["role_name"]) for m in d])'
