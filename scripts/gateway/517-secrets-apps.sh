#!/bin/bash
set -uo pipefail
echo "=== podinfo / webapp 现网 pods 镜像 ==="
kubectl get pods -n podinfo -o custom-columns=NAME:.metadata.name,IMAGE:..image 2>/dev/null | head -10
kubectl get pods -n webapp -o custom-columns=NAME:.metadata.name,IMAGE:..image 2>/dev/null | head -10
echo "=== harbor-regcred 的 dockerconfigjson 结构（只打 key，不打值） ==="
for ns in podinfo webapp; do
  J=$(kubectl -n $ns get secret harbor-regcred -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d)
  if [ -n "$J" ]; then echo "  ns=$ns keys: $(echo "$J" | python3 -c 'import sys,json;print(list(json.load(sys.stdin)["auths"].keys()))')"; else echo "  ns=$ns 无 harbor-regcred"; fi
done
echo "=== ArgoCD Applications 指向 ==="
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,PATH:.spec.source.path,BRANCH:.spec.source.targetRevision,NS:.spec.destination.namespace
echo "=== verify-image.sh 如何校验 ==="
curl -s -k -H "PRIVATE-TOKEN: __GITLAB_PAT__" "https://gitlab.corp.local/api/v4/projects/2/repository/files/ci%2Fverify-image.sh/raw?ref=main"
