#!/bin/bash
set -uo pipefail
echo "=== envFrom 是否已加上 ==="
kubectl -n jenkins get deploy jenkins -o yaml | grep -A3 envFrom
echo "=== Deployment 现有 env 与 envFrom ==="
kubectl -n jenkins get deploy jenkins -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0]
print("env names:", [e["name"] for e in d.get("env",[])])
print("envFrom:", d.get("envFrom"))'

echo "=== ConfigMap 中是否只剩占位 ==="
kubectl -n jenkins get cm jenkins-casc -o json | python3 -c '
import sys,json,base64,re
y=base64.b64decode(json.load(sys.stdin)["data"]["jenkins.yaml"]).decode()
plain=[l for l in y.splitlines() if re.search(r"(glpat|squ_|cyvRD|QFMiV|Artifactory@|BreakGlass@|JenkinsOIDC@)", l)]
print("明文行数:", len(plain))
for l in plain: print("  !!", l.strip()[:80])
print("占位行:")
[print("  ", l.strip()) for l in y.splitlines() if "${" in l]'

echo "=== rollout restart + 等待 Ready ==="
kubectl -n jenkins rollout restart deploy/jenkins
kubectl -n jenkins rollout status deploy/jenkins --timeout=300s
