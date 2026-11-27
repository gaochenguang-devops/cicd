#!/bin/bash
set -uo pipefail
A='http://192.168.200.12:30092/artifactory'
ADM='admin:__ARTIFACTORY_ADMIN_PASS__'
U='jenkins-ci'
P='JenkinsCi@2026Upload'

echo "=== 1) 建专用用户 $U（非管理员） ==="
curl -sS -o /tmp/u.out -w 'create_user=%{http_code}\n' -u "$ADM" -H 'Content-Type: application/json' \
  -X POST "$A/api/security/users/$U" \
  -d '{"name":"jenkins-ci","password":"'"$P"'","email":"jenkins-ci@corp.local","admin":false,"profileUpdatable":false,"internalPasswordDisabled":false,"realm":"internal"}'
cat /tmp/u.out; echo
curl -sS -u "$ADM" "$A/api/security/users/$U" | python3 -m json.tool | head -20

echo "=== 2) 用该用户试上传（预期 403：OSS 无默认权限） ==="
echo hi > /tmp/u.txt
curl -sS -o /dev/null -w 'upload_asis=%{http_code}\n' -u "$U:$P" -T /tmp/u.txt \
  "$A/build-artifacts/maven-demo/_probe/u.txt"

echo "=== 3) 建权限目标 build-artifacts（仅该用户） ==="
curl -sS -o /tmp/pt.out -w 'create_perm=%{http_code}\n' -u "$ADM" -H 'Content-Type: application/json' \
  -X PUT "$A/api/security/permissions/build-artifacts-jenkins" \
  -d '{"name":"build-artifacts-jenkins","includesPattern":"**","excludesPattern":"",
      "repositories":["build-artifacts"],
      "principals":{"users":{"jenkins-ci":["read","write","annotate","delete","manage"]}}}'
cat /tmp/pt.out; echo

echo "=== 4) 再试上传 ==="
curl -sS -o /dev/null -w 'upload_after_perm=%{http_code}\n' -u "$U:$P" -T /tmp/u.txt \
  "$A/build-artifacts/maven-demo/_probe/u.txt"
echo "=== 5) 读回 + 删除试写文件 ==="
curl -sS -o /dev/null -w 'readback=%{http_code}\n' -u "$U:$P" "$A/build-artifacts/maven-demo/_probe/u.txt"
curl -sS -o /dev/null -w 'cleanup=%{http_code}\n' -u "$U:$P" -X DELETE "$A/build-artifacts/maven-demo/_probe/u.txt"
