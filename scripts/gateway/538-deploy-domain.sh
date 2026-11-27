#!/bin/bash
set -uo pipefail
python3 - <<'PY'
import json, ssl, urllib.request, urllib.parse
PAT="__GITLAB_PAT__"; G="https://gitlab.corp.local/api/v4"
ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
def get(path, ref="deploy"):
    return urllib.request.urlopen(urllib.request.Request(G+f"/projects/2/repository/files/{urllib.parse.quote(path,safe='')}/raw?ref={ref}", headers={"PRIVATE-TOKEN":PAT}), context=ctx, timeout=30).read().decode()
def put(path, content, msg):
    body=json.dumps({"branch":"deploy","commit_message":msg,"content":content}).encode()
    r=urllib.request.Request(G+f"/projects/2/repository/files/{urllib.parse.quote(path,safe='')}", data=body,
        headers={"PRIVATE-TOKEN":PAT,"Content-Type":"application/json"}, method="PUT")
    return urllib.request.urlopen(r, context=ctx, timeout=30).read().decode()

for p,msg in [
  ("deploy/podinfo/kustomization.yaml","deploy: podinfo 镜像改用 https 域名"),
  ("deploy/webapp/kustomization.yaml","deploy: webapp 镜像改用 https 域名"),
  ("deploy/podinfo/redis.yaml","deploy: redis 镜像改用 https 域名"),
]:
    c=get(p)
    c2=c.replace("192.168.200.12:30090","harbor.corp.local")
    put(p,c2,msg)
    print("  已更新", p, "剩余 IP 引用:", c2.count("192.168.200.12:30090"))
PY
for a in podinfo webapp; do kubectl -n argocd annotate application $a argocd.argoproj.io/refresh=normal --overwrite >/dev/null; done
for i in $(seq 1 14); do
  sleep 10
  R=$(kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.revision}')
  echo "[$((i*10))s] rev=${R:0:8}"
  [ "${R:0:8}" != "6190a6cb" ] && break
done
sleep 10
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
kubectl get pods -n podinfo -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:..image --no-headers
kubectl get pods -n webapp -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:..image --no-headers
