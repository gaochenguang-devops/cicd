#!/bin/bash
set -uo pipefail
kubectl -n default delete pod maven-demo-pullprobe --ignore-not-found >/dev/null
kubectl -n default delete secret harbor-pull-probe --ignore-not-found >/dev/null
echo "临时资源已清理"
echo "=== 两个测试 tag 是否残留 ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' "http://192.168.200.12:30090/api/v2.0/projects/apps/repositories/maven-demo/artifacts?page_size=20" | python3 -c 'import sys,json
for a in json.load(sys.stdin): print(" ", [t["name"] for t in (a["tags"] or [])])'
