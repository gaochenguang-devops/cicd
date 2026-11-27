#!/bin/bash
set -uo pipefail
echo "=== speaker 日志中的 L2/ARP/memberlist 相关 ==="
kubectl -n metallb-system logs ds/speaker 2>&1 | grep -iE 'l2|announc|arp|memberlist|ml-|secret|error|warn|register|starting' | head -40
echo "=== speaker Pod 规格（hostNetwork / 权限 / 环境） ==="
kubectl -n metallb-system get ds speaker -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=d["spec"]["template"]["spec"]
print("  hostNetwork:", s.get("hostNetwork"))
print("  serviceAccount:", s.get("serviceAccountName"))
c=s["containers"][0]
print("  args:", c.get("args"))
print("  env:", [(e.get("name"), "secretKeyRef" if "valueFrom" in e else e.get("value")) for e in c.get("env",[])])
print("  sc:", json.dumps(c.get("securityContext",{})))
print("  volumeMounts:", [m.get("mountPath") for m in c.get("volumeMounts",[])])
print("  volumes:", [(v.get("name"), list((v.get("secret") or {}).keys()) or list((v.get("configMap") or {}).keys())) for v in s.get("volumes",[])])
'
echo "=== memberlist secret 是否存在 ==="
kubectl -n metallb-system get secret 2>&1
echo "=== speaker Pod 事件（含重启/挂载） ==="
kubectl -n metallb-system describe pod -l component=speaker | grep -A12 'Events:' | head -16
