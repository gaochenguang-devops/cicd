#!/bin/bash
set -uo pipefail
echo "=== Grafana pod 现状 ==="
kubectl -n monitoring get pods -l app=grafana -o wide --no-headers
kubectl -n monitoring describe pod -l app=grafana 2>/dev/null | tail -12
echo "=== 最近事件 ==="
kubectl -n monitoring get events --sort-by=.lastTimestamp 2>/dev/null | grep -E "grafana|blackbox" | tail -8

echo "=== 重建 dashboards CM（超过 256KB 不能走 apply 注解，改用 create --save-config=false） ==="
kubectl -n monitoring delete cm grafana-dashboards --ignore-not-found >/dev/null
kubectl -n monitoring create cm grafana-dashboards --from-file=/root/grafana-dash/normalized --save-config=false
kubectl -n monitoring get cm grafana-dashboards -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("  keys:", list(d.keys()), "总字节:", sum(len(v) for v in d.values()))
'

