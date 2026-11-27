#!/usr/bin/env bash
set -eu
python3 - <<'PY'
import subprocess,json
d=json.loads(subprocess.check_output(["kubectl","-n","argocd","get","cm","argocd-cm","-o","json"]))
cm=d["data"]
cm.pop("oidc.config",None)
cm["dex.config"]="""connectors:
- type: oidc
  id: keycloak
  name: Keycloak
  config:
    issuer: http://192.168.200.12:30087/realms/corp
    clientID: argocd-dex
    clientSecret: __ARGOCD_DEX_OIDC_SECRET__
    insecureEnableHTTP: true
    insecureSkipEmailVerified: true
    getUserInfo: true
    scopes:
    - openid
    - profile
    - email
    - groups
oauth2:
  skipApprovalScreen: true
"""
json.dump(d,open("/tmp/acm2.json","w"))
print("dex.config written")
PY
kubectl apply -f /tmp/acm2.json >/dev/null
kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-dex-server >/dev/null
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=120s | tail -1
kubectl -n argocd rollout status deploy/argocd-server --timeout=120s | tail -1
