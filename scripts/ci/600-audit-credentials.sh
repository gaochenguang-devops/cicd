#!/bin/bash
set -uo pipefail
GL=http://192.168.200.12/api/v4
TOK='__GITLAB_PAT__'

echo "=== 1. GitLab 项目级 CI 变量（masked/protected/environment 范围） ==="
for pid in 2 1 4; do
  name=$(curl -s -H "PRIVATE-TOKEN: $TOK" "$GL/projects/$pid" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path_with_namespace"])')
  echo "--- project $pid ($name)"
  curl -s -H "PRIVATE-TOKEN: $TOK" "$GL/projects/$pid/variables" \
   | python3 -c '
import json,sys
vs=json.load(sys.stdin)
if not vs: print("    (无变量)")
for v in vs:
    print("    %-22s masked=%-5s protected=%-5s env=%-10s type=%s" % (v["key"], v["masked"], v["protected"], v.get("environment_scope","*"), v["variable_type"]))
' 2>/dev/null || echo "    (解析失败)"
done

echo "=== 2. 实例级/群组级变量（是否有越权全局变量） ==="
curl -s -H "PRIVATE-TOKEN: $TOK" "$GL/admin/ci/variables" | head -c 300; echo

echo "=== 3. K8s Secret jenkins-casc-secrets 键清单（对照用） ==="
kubectl -n jenkins get secret jenkins-casc-secrets -o jsonpath='{range .data.*}{@}{"\n"}{end}' >/dev/null 2>&1
kubectl -n jenkins get secret jenkins-casc-secrets -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]
for k in sorted(d): print("    %-22s bytes=%d" % (k, len(d[k])))
'

echo "=== 4. Jenkins 任务描述（方案 A 标注） ==="
curl -s -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' 'http://192.168.200.12:30088/job/maven-demo-pipeline/api/json?tree=name,description' | python3 -m json.tool 2>/dev/null || echo "  取不到"
