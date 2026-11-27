#!/bin/bash
set -uo pipefail
echo "=== 不含 exclude 的 debug 决策行 ==="
kubectl -n metallb-system logs ds/speaker 2>&1 \
 | grep -iE 'shouldAnnounce|announcing|announce|notOwner|l2 advertisement|pool|gateway|memberlist|leader|error|warn' \
 | grep -v 'announced interface to exclude' \
 | python3 -c '
import json,sys
for line in sys.stdin:
    try:
        d=json.loads(line)
    except:
        print("  RAW:",line.strip()[:200]);continue
    keys=("event","service","ip","node","interface","reason","error","msg")
    print("  [%s] %s" % (d.get("level"), " | ".join("%s=%s"%(k,d[k]) for k in keys if k in d)[:230]))
' | tail -40
