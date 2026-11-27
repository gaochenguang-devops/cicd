#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
echo "=== harbor project apps 是否公开 ==="
curl -s -k -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects/apps" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  metadata.public =", (d.get("metadata") or {}).get("public"))'
echo "=== deploy/podinfo/kustomization.yaml ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/files/deploy%2Fpodinfo%2Fkustomization.yaml/raw?ref=deploy"
echo "=== deploy/webapp/kustomization.yaml ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/files/deploy%2Fwebapp%2Fkustomization.yaml/raw?ref=deploy"
echo "=== ci/update-manifest.sh 里与 registry 有关的行 ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/2/repository/files/ci%2Fupdate-manifest.sh/raw?ref=main" | grep -nE "HARBOR|newName|registry|sed" | head -20
echo "=== 现网 pod 的 image 与 pull secret ==="
kubectl get pods -A -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)
for p in d["items"]:
    for c in p["spec"].get("containers",[]):
        if "207" in c["image"] or "harbor" in c["image"]: 
            print("  ", p["metadata"]["namespace"], p["metadata"]["name"], c["image"], [s["name"] for s in p["spec"].get("imagePullSecrets",[])])
'
