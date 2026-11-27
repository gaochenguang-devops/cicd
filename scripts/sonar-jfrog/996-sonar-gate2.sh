#!/usr/bin/env bash
set -uo pipefail
S=http://127.0.0.1:30091
A="-u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__""
for id in $(curl -s $A "$S/api/qualitygates/show?name=cicd-gate" | python3 -c 'import sys,json;print(" ".join(c["id"] for c in json.load(sys.stdin)["conditions"]))'); do
  printf "del %s -> %s\n" "$id" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/qualitygates/delete_condition --data-urlencode "id=$id")"
done
for m in new_reliability_rating new_security_rating new_maintainability_rating; do
  printf "add %s -> %s\n" "$m" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/qualitygates/create_condition --data-urlencode "gateName=cicd-gate" --data-urlencode "metric=$m" -d 'op=GT' -d 'error=1')"
done
sleep 2
curl -s $A "$S/api/qualitygates/show?name=cicd-gate" | head -c 500; echo
curl -s $A "$S/api/qualitygates/list" | python3 -c 'import sys,json;print([(q["name"],q["isDefault"]) for q in json.load(sys.stdin)["qualitygates"]])'
