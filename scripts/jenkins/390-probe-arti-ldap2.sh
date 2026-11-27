#!/bin/bash
set -uo pipefail
A='http://192.168.200.12:30092/artifactory'
P='__LDAP_USER_INIT_PASS__'
echo probe > /tmp/ldap.txt
echo "=== 非 admin LDAP 账号（dev01/ops01/qa01）上传测试 ==="
for U in dev01 ops01 qa01 gaofei; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$U:$P" -T /tmp/ldap.txt "$A/build-artifacts/maven-demo/_probe/$U.txt")
  echo "  PUT $U -> $code"
done
echo "=== 同账号读取测试 ==="
curl -s -o /dev/null -w '  GET dev01 -> %{http_code}\n' -u "dev01:$P" "$A/build-artifacts/maven-demo/main/1.0.6/maven-demo.jar"
echo "=== 匿名读 ==="
curl -s -o /dev/null -w '  GET 匿名 -> %{http_code}\n' "$A/build-artifacts/maven-demo/main/1.0.6/maven-demo.jar"
