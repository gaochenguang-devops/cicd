#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
for u in \
 "$J/credentials/store/system/domain/_/api/json?tree=credentials%5Bid%2CtypeName%5D" \
 "$J/manage/credentials-store/system/domain/_/api/json" \
 "$J/api/json?tree=mode,jobs%5Bname%5D" ; do
  code=$(curl -s -o /tmp/o.txt -w '%{http_code}' -u "$AU" "$u")
  echo "== $u -> $code size=$(wc -c </tmp/o.txt)"
  head -c 200 /tmp/o.txt; echo
done
echo "=== 页面 grep ==="
curl -s -u "$AU" "$J/manage/credentials/" | grep -oE '(gitlab-pat|harbor-jenkins-ci|harbor-lib-pull|sonar-token|artifactory-admin)' | sort -u
echo "=== 共享库页面 ==="
curl -s -u "$AU" "$J/manage/configureTools/" -o /dev/null -w 'tools=%{http_code}\n'
curl -s -u "$AU" "$J/descriptorByName/org.jenkinsci.plugins.workflow.libs.GlobalLibraries/api/json" | head -c 500; echo
