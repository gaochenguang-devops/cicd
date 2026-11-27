#!/bin/bash
set -uo pipefail
KP=$(kubectl -n keycloak get pod -o name | grep -v db | grep -v Terminating | head -1)

echo "===== 1. 修 ArgoCD：argocd-dex client 的 redirectUris ====="
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1 || exit 1
ID=$($KC get clients -r corp -q clientId=argocd-dex --fields id --format csv --noquotes | tail -1)
$KC update clients/$ID -r corp \
  -s "redirectUris=[\"https://argocd.corp.local/api/dex/callback\",\"http://192.168.200.12:30080/api/dex/callback\"]" \
  -s "webOrigins=[\"https://argocd.corp.local\",\"http://192.168.200.12:30080\"]" >/dev/null 2>&1 && echo "  argocd-dex 已更新"
$KC get clients -r corp -q clientId=argocd-dex --fields redirectUris 2>&1 | tr -d "\n" | head -c 200; echo
'

echo "===== 2. Harbor：把 EXT_ENDPOINT 设回 https，测 podman login 与 realm ====="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
python3 - <<'PY'
import subprocess, json
cm = json.loads(subprocess.check_output(["kubectl","-n","harbor","get","cm","harbor-core","-o","json"]))
d = cm["data"]
d["EXT_ENDPOINT"] = "https://harbor.corp.local"
cm["data"] = d
for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
    cm["metadata"].pop(k, None)
cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration",None)
open("/tmp/harbor-cm3.json","w").write(json.dumps(cm))
PY
kubectl replace -f /tmp/harbor-cm3.json --force | tail -1
kubectl -n harbor rollout restart deploy/harbor-core >/dev/null
kubectl -n harbor rollout status deploy/harbor-core --timeout=120s | tail -1
sleep 8
echo "--- Harbor 现在发出的 redirect_uri ---"
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login -m 15 | grep -i '^location' | tr -d '\r' | sed 's/.*redirect_uri=\([^&]*\).*/  redirect_uri=\1/' | head -1
echo "--- registry 401 realm（podman 会用这个） ---"
curl -s -i http://192.168.200.12:30090/v2/ -m 8 | grep -i 'www-authenticate' | head -1
echo "--- podman login 到 192.168.200.12:30090（admin 本地口令） ---"
echo '__HARBOR_ADMIN_PASS__' | podman login --tls-verify=false -u admin --password-stdin 192.168.200.12:30090 2>&1 | tail -2
echo "--- podman login 到 https://harbor.corp.local（走网关 + 系统 CA） ---"
echo '__HARBOR_ADMIN_PASS__' | podman login -u admin --password-stdin harbor.corp.local 2>&1 | tail -2
