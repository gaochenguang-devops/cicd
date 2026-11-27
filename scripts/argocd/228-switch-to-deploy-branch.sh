#!/usr/bin/env bash
# 把 podinfo / webapp 两个 Application 的 source 从 main 切到 deploy 分支
set -uo pipefail
echo "===== 1. 切换前状态 ====="
for a in podinfo webapp; do
  kubectl -n argocd get application $a -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  %-8s rev=%s path=%s status=%s/%s"%(d["metadata"]["name"], d["spec"]["source"].get("targetRevision"), d["spec"]["source"].get("path"),
      d.get("status",{}).get("sync",{}).get("status"), d.get("status",{}).get("health",{}).get("status")))
'
done

echo "===== 2. 打补丁 ====="
for a in podinfo webapp; do
  kubectl -n argocd patch application $a --type merge \
    -p '{"spec":{"source":{"targetRevision":"deploy"}}}' >/dev/null && echo "  $a: targetRevision=deploy"
done

echo "===== 3. 硬刷新并等待 ====="
for a in podinfo webapp; do
  kubectl -n argocd patch application $a --type merge \
    -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\",\"kb.refresh-time\":\"$(date +%s)\"}}}" >/dev/null
done
sleep 12

echo "===== 4. 切换后状态 ====="
for a in podinfo webapp; do
  kubectl -n argocd get application $a -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=d.get("status",{})
r=s.get("sync",{}).get("revision","")
print("  %-8s rev=%s deployed_rev=%s status=%s/%s msg=%s"%(d["metadata"]["name"], d["spec"]["source"].get("targetRevision"),
      r[:8], s.get("sync",{}).get("status"), s.get("health",{}).get("status"), (s.get("conditions") or [{}])[0].get("message","")[:60]))
'
done

echo "===== 5. 集群里实际镜像 ====="
kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' | sed 's/^/  podinfo: /'
kubectl -n webapp get deploy -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image' | sed 's/^/  /'
echo "  运行中 pod 数: $(kubectl -n podinfo get pods --no-headers | grep -c Running) (podinfo) / $(kubectl -n webapp get pods --no-headers | grep -c Running) (webapp)"
