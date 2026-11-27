#!/usr/bin/env bash
set -eu
export KUBECONFIG=/root/.kube/config
TS=$(date +%Y%m%d-%H%M%S)
BAK=/root/argocd-oidc-bak-$TS
mkdir -p $BAK
kubectl -n argocd get cm argocd-cm -o yaml > $BAK/argocd-cm.yaml
kubectl -n argocd get cm argocd-rbac-cm -o yaml > $BAK/argocd-rbac-cm.yaml
echo "backup -> $BAK"

kubectl -n argocd get cm argocd-cm -o json > /tmp/cm.json
python3 - <<'PY'
import json
cm=json.load(open("/tmp/cm.json"))
d=cm["data"]
d.pop("dex.config",None)
d["url"]="http://192.168.200.12:30080"
d["oidc.config"]="""name: Keycloak
issuer: http://192.168.200.12:30087/realms/corp
clientID: argocd
clientSecret: ArgoCDOIDC@2026Secret
requestedScopes:
- groups
requestedIDTokenClaims:
  groups:
    essential: true
"""
json.dump(cm,open("/tmp/cm-new.json","w"))
PY
python3 -c "import json;cm=json.load(open('/tmp/cm-new.json'));cm['metadata']={'name':cm['metadata']['name'],'namespace':cm['metadata']['namespace']};print(json.dumps(cm))" > /tmp/cm-patch.json
kubectl apply -f /tmp/cm-patch.json
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.oidc\.config}'; echo
kubectl -n argocd rollout restart deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
