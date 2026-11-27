#!/bin/bash
set -uo pipefail
echo "=== 用 IP:NodePort 拉私有镜像（当前 EXT_ENDPOINT=https 后是否已坏） ==="
crictl pull 192.168.200.12:30090/apps/podinfo:dfa6136fc7d0c0ff825c33d74aaa38ad818c13d4 2>&1 | tail -3
echo
echo "=== 全集群仍在用 192.168.200.12:30090 的 pod ==="
kubectl get pods -A -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)
for p in d["items"]:
    hits=[c["image"] for c in p["spec"].get("containers",[]) if "192.168.200.12:30090" in c["image"]]
    if hits: print("  ", p["metadata"]["namespace"]+"/"+p["metadata"]["name"], hits)
'
echo "=== 哪些 namespace 有 harbor-regcred ==="
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n $ns get secret harbor-regcred >/dev/null 2>&1 && echo "  $ns"
done
