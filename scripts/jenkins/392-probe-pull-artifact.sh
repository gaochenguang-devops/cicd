#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
A='http://192.168.200.12:30092/artifactory'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
N=$(curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastSuccessfulBuild/api/json?tree=number" | python3 -c 'import sys,json;print(json.load(sys.stdin)["number"])')
echo "lastSuccessfulBuild=$N"

echo "=== 1) Jenkins 归档制品（指定构建，Basic 认证） ==="
curl -s -o /tmp/j1.jar -w '  code=%{http_code} size=%{size_download}\n' -u "$AU" "$J/job/maven-demo-pipeline/$N/artifact/target/maven-demo.jar"

echo "=== 2) lastSuccessfulBuild 直接拿（不看构建号） ==="
curl -sL -o /tmp/j2.jar -w '  code=%{http_code} size=%{size_download}\n' -u "$AU" "$J/job/maven-demo-pipeline/lastSuccessfulBuild/artifact/target/maven-demo.jar"

echo "=== 3) 匿名访问（预期 403/401） ==="
curl -s -o /dev/null -w '  anon=%{http_code}\n' "$J/job/maven-demo-pipeline/$N/artifact/target/maven-demo.jar"

echo "=== 4) 列出本次归档清单（API） ==="
curl -s -u "$AU" "$J/job/maven-demo-pipeline/$N/api/json?tree=artifacts%5BfileName%2CrelativePath%5D"; echo

echo "=== 5) Artifactory 直接下载（无认证/认证） ==="
curl -s -o /dev/null -w '  anon=%{http_code}\n' "$A/build-artifacts/maven-demo/main/1.0.$N/maven-demo.jar"
curl -s -o /tmp/a1.jar -w '  basic=%{http_code} size=%{size_download}\n' -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "$A/build-artifacts/maven-demo/main/1.0.$N/maven-demo.jar"
curl -s -o /tmp/a1b.jar -w '  ldap_dev01=%{http_code} size=%{size_download}\n' -u 'dev01:__LDAP_USER_INIT_PASS__' "$A/build-artifacts/maven-demo/main/1.0.$N/maven-demo.jar"

echo "=== 6) 两处 jar 是否同一份 ==="
sha256sum /tmp/j1.jar /tmp/j2.jar /tmp/a1.jar /tmp/a1b.jar | awk '{print "  "$1" "$2}'
