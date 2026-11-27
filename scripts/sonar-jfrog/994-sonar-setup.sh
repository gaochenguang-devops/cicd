#!/usr/bin/env bash
set -uo pipefail
S=http://127.0.0.1:30091
A="-u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__""

for g in platform-admins devops developers qa; do
  printf "group %s -> %s\n" "$g" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/user_groups/create -d "name=$g")"
done
for g in platform-admins devops; do
  printf "admin perm %s -> %s\n" "$g" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/permissions/add_group --data-urlencode "groupName=$g" -d "permission=admin")"
done
for g in developers qa; do
  printf "scan perm %s -> %s\n" "$g" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/permissions/add_group --data-urlencode "groupName=$g" -d "permission=scan")"
done

printf "project -> %s\n" "$(curl -s -o /dev/null -w '%{http_code}' $A -X POST $S/api/projects/create -d 'project=podinfo' -d 'name=podinfo')"

echo "== token =="
curl -s $A -X POST $S/api/user_tokens/generate -d 'name=ci-jenkins' | tee /tmp/sonar_token.json
echo
echo "== quality gate =="
curl -s $A "$S/api/qualitygates/list" | python3 -c 'import sys,json;d=json.load(sys.stdin);print([(q["name"],q["isDefault"]) for q in d["qualitygates"]])'
