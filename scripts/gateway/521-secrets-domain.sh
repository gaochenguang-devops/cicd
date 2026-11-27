#!/bin/bash
set -uo pipefail
echo "=== 所有用 IP:30090 镜像的对象（kind/ns/name/image） ==="
kubectl get deploy,sts,ds,rs,cronjob,job -A -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)
for o in d["items"]:
    k=o["kind"]; n=o["metadata"]["name"]; ns=o["metadata"]["namespace"]
    spec=o.get("spec",{})
    if k=="CronJob": tpl=spec.get("jobTemplate",{}).get("spec",{}).get("template",{}).get("spec",{})
    else: tpl=spec.get("template",{}).get("spec",{})
    imgs=[]
    for c in (tpl or {}).get("containers",[])+ (tpl or {}).get("initContainers",[]) if tpl else []:
        if "192.168.200.12:30090" in c["image"]: imgs.append(c["name"]+"="+c["image"])
    if imgs: print("  ",k,ns+"/"+n,imgs)
'
echo
echo "=== 给 harbor-regcred 加 harbor.corp.local 凭据（保留原 IP key） ==="
for ns in podinfo webapp jenkins keycloak kube-system; do
python3 - "$ns" <<'PY'
import sys, json, base64, subprocess
ns = sys.argv[1]
raw = subprocess.check_output(["kubectl","-n",ns,"get","secret","harbor-regcred","-o","jsonpath={.data.\\.dockerconfigjson}"])
raw = raw.decode() if isinstance(raw,bytes) else raw
d = json.loads(base64.b64decode(raw).decode())
auths = d.get("auths",{})
if "harbor.corp.local" not in auths:
    src = auths.get("192.168.200.12:30090")
    if src: auths["harbor.corp.local"] = src
json.dump(d, open("/tmp/dc_%s.json"%ns,"w"))
PY
  kubectl -n $ns create secret docker-registry harbor-regcred --from-file=.dockerconfigjson=/tmp/dc_$ns.json --dry-run=client -o yaml \
    | kubectl -n $ns apply -f - >/dev/null && echo "  $ns 已更新"
done
