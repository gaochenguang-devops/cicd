#!/usr/bin/env bash
set -uo pipefail
echo "== Artifactory 制品 =="
curl -s -u admin:'__ARTIFACTORY_ADMIN_PASS__' 'http://127.0.0.1:30092/artifactory/api/storage/build-artifacts/podinfo?list&deep=1&listFolders=0' \
 | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(" ",f["uri"],f.get("size")) for f in d.get("files",[])]' 2>/dev/null || echo "list fail"
echo
echo "== Sonar 门禁 =="
curl -s -u "__SONAR_ADMIN_USER__:__SONAR_ADMIN_PASS__" 'http://127.0.0.1:30091/api/qualitygates/project_status?projectKey=podinfo' \
 | python3 -c 'import sys,json;d=json.load(sys.stdin)["projectStatus"];print(d["status"]);[print(" ",c["metricKey"],c["status"],c.get("actualValue")) for c in d["conditions"]]'
echo
echo "== ArgoCD =="
kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.status} {.status.health.status} image={.status.summary.images}{"\n"}' 2>/dev/null || echo "no app"
echo "== 运行中的镜像 =="
kubectl -n podinfo get deploy -o jsonpath='{range .items[*]}{.metadata.name} {.spec.template.spec.containers[0].image}{"\n"}{end}' 2>/dev/null
echo "== 制品 URL 直读 =="
TAG=$(kubectl -n podinfo get deploy -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')
curl -s -o /dev/null -w "artifact HEAD=$TAG -> %{http_code}\n" -u admin:'__ARTIFACTORY_ADMIN_PASS__' "http://127.0.0.1:30092/artifactory/build-artifacts/podinfo/main/$TAG/podinfo-$TAG.tar.gz"
