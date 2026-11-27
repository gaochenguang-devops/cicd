#!/bin/bash
set -uo pipefail
echo "=== apps ns secrets ==="
kubectl -n apps get secrets | awk '{print $1,$2}'
SEC=$(kubectl -n apps get secrets -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -i -E 'harbor|regcred|registry' | head -1)
echo "找到 secret: ${SEC:-none}"
if [ -n "${SEC:-}" ]; then
  kubectl -n apps get secret "$SEC" -o jsonpath='{.type}'; echo
  echo "=== 用该 secret 在 default 建临时 secret 并试拉镜像 ==="
  kubectl -n apps get secret "$SEC" -o yaml | sed 's/namespace: apps/namespace: default/' | kubectl apply -f - >/dev/null
  kubectl -n default run pulltest-probe --rm -i --restart=Never \
    --image=192.168.200.12:30090/apps/maven-demo:1.0.6 \
    --overrides='{"spec":{"imagePullSecrets":[{"name":"'"$SEC"'"}],"containers":[{"name":"pulltest-probe","image":"192.168.200.12:30090/apps/maven-demo:1.0.6","command":["java","-version"]}]}}' 2>&1 | tail -6
fi
