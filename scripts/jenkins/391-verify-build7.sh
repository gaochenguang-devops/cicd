#!/bin/bash
set -uo pipefail
V=1.0.7
echo "=== build #7 产物复核 ==="
echo "-- Harbor"
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' "http://192.168.200.12:30090/api/v2.0/projects/apps/repositories/maven-demo/artifacts?page_size=5" | python3 -c 'import sys,json
for a in json.load(sys.stdin): print("  ",[t["name"] for t in (a["tags"] or [])], a["digest"][:19])'
echo "-- Artifactory 三件"
for f in maven-demo.jar maven-demo.jar.sha256 build-info.json; do
  echo "  $f -> $(curl -s -o /dev/null -w '%{http_code}' -I -u 'admin:__ARTIFACTORY_ADMIN_PASS__' http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/$V/$f)"
done
echo "-- build-info"
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/$V/build-info.json"; echo
echo "-- 清理探测残留 _probe"
curl -s -o /dev/null -w '  del_probe_dir=%{http_code}\n' -u 'admin:__ARTIFACTORY_ADMIN_PASS__' -X DELETE "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/_probe"
curl -s -o /dev/null -w '  probe_exists=%{http_code}\n' -I -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/_probe/"
