#!/bin/bash
set -uo pipefail
echo "=== metallb CRD 列表 ==="
kubectl get crd | grep -i metallb
echo "=== ServiceL2Status（按 namespace 查） ==="
kubectl get servicel2status -A -o wide 2>&1 | head -5
for ns in gateway monitoring; do echo "--- $ns"; kubectl get servicel2status -n $ns -o yaml 2>&1 | head -12; done
echo "=== speaker 错误/警告日志 ==="
kubectl -n metallb-system logs ds/speaker 2>&1 | python3 -c '
import json,sys
for line in sys.stdin:
    try: d=json.loads(line)
    except: continue
    lvl=d.get("level","")
    if lvl in ("error","warn"):
        print("  [%s] %s %s" % (lvl, d.get("msg","")[:110], str({k:v for k,v in d.items() if k in ("event","interface","service","ip","error")})[:120]))
' | head -20
echo "=== 节点状态 ==="
kubectl get node -o wide
echo "=== speaker 内的 memberlist 监听 ==="
ss -lunp 2>/dev/null | grep 7946 || echo "  7946 未监听"
echo "=== ip neigh（节点对 .210 的认知） ==="
ip neigh show | grep -E '192.168.200.21[0-5]' || echo "  无"
