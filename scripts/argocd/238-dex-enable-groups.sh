#!/usr/bin/env bash
set -eu
python3 - <<'PY'
import subprocess,json
d=json.loads(subprocess.check_output(["kubectl","-n","argocd","get","cm","argocd-cm","-o","json"]))
cm=d["data"]
cm["dex.config"]=cm["dex.config"].replace("    insecureSkipEmailVerified: true","    insecureSkipEmailVerified: true\n    insecureEnableGroups: true")
json.dump(d,open("/tmp/acm3.json","w"))
print(cm["dex.config"])
PY
kubectl apply -f /tmp/acm3.json >/dev/null
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server >/dev/null
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=120s | tail -1
kubectl -n argocd rollout status deploy/argocd-server --timeout=120s | tail -1
