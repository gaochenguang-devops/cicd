#!/bin/bash
set -uo pipefail
echo "=== K8s Secret jenkins-casc-secrets（CI 凭据实际值） ==="
kubectl -n jenkins get secret jenkins-casc-secrets -o json | python3 -c '
import sys,json,base64
d=json.load(sys.stdin)["data"]
for k,v in sorted(d.items()):
    print("  %-22s %s" % (k, base64.b64decode(v).decode()))
'
echo "=== GitLab CI 变量（project root/podinfo=2） ==="
GL="__GITLAB_PAT__"
curl -s --header "PRIVATE-TOKEN: $GL" 'http://192.168.200.12/api/v4/projects/2/variables' | python3 -c '
import sys,json
try:
    for v in json.load(sys.stdin): print("  %-20s %s%s" % (v["key"], v["value"], "  [masked]" if v.get("masked") else ""))
except Exception as e: print("  失败:",e)
'
echo "=== Harbor robot 账号 ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/robots' | python3 -c '
import sys,json
try:
    for r in json.load(sys.stdin): print("  %-40s level=%s projects=%s" % (r["name"], r.get("level"), [p.get("name") for p in (r.get("project_list") or [])]))
except Exception as e: print("  失败:",e)
'
echo "=== 网关 htpasswd 文件位置与来源 ==="
kubectl -n gateway get deploy gateway -o jsonpath='{range .spec.template.spec.containers[0].volumeMounts[*]}{.name} {.mountPath}{"\n"}{end}'

