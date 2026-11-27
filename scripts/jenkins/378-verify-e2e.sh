#!/bin/bash
set -uo pipefail
V=1.0.6
echo "=== 1. Harbor 镜像 ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' "http://192.168.200.12:30090/api/v2.0/projects/apps/repositories/maven-demo/artifacts?page_size=10" \
 | python3 -c 'import sys,json
d=json.load(sys.stdin)
for a in d: print(" tag=",a["tags"] and [t["name"] for t in a["tags"]], "digest=",a["digest"][:19], "size=",a["size"])'

echo "=== 2. Artifactory 制品目录 ==="
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/api/storage/build-artifacts/maven-demo/main/$V/" \
 | python3 -c 'import sys,json
d=json.load(sys.stdin)
for f in d.get("children",[]): print(" ",f["uri"],f.get("size"))'

echo "=== 3. jar 与 sha256 一致性（下载回读校验） ==="
cd /tmp && rm -f vjar.jar vjar.sha256
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' -o vjar.jar "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/$V/maven-demo.jar"
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' -o vjar.sha256 "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/$V/maven-demo.jar.sha256"
echo "  jar 实际 sha256 = $(sha256sum vjar.jar | cut -d' ' -f1)"
echo "  .sha256 文件内  = $(cut -d' ' -f1 vjar.sha256)"
echo "  大小 = $(stat -c%s vjar.jar) 字节"

echo "=== 4. build-info.json ==="
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/$V/build-info.json"; echo

echo "=== 5. Sonar 门禁 ==="
curl -s -u 'sonaradmin:__SONAR_ADMIN_PASS__' "http://192.168.200.12:30091/api/qualitygates/project_status?projectKey=maven-demo" \
 | python3 -c 'import sys,json;d=json.load(sys.stdin)["projectStatus"];print("  status=",d["status"]);[print("   -",c["metricKey"],c["status"],c["actualValue"]) for c in d["conditions"]]'
echo "=== 6. 镜像可在集群内拉取（pull 测试） ==="
kubectl -n default run pulltest-$RANDOM --rm -i --restart=Never --image=192.168.200.12:30090/apps/maven-demo:$V --command -- echo image-ok 2>&1 | tail -3
