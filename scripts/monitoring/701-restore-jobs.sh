#!/bin/bash
set -uo pipefail
echo "=== 1. 应用修正后的 prometheus-config（补齐 grafana / keycloak / blackbox 三个 job） ==="
kubectl apply -f /root/gw-manifests/monitoring-30-prometheus.yaml | tail -3
kubectl -n monitoring rollout status deploy/prometheus --timeout=150s | tail -1
sleep 15
echo "=== 2. 目标数应回到 21 ==="
curl -s http://10.98.134.245:9090/api/v1/targets?state=active | python3 -c '
import sys,json,collections
t=json.load(sys.stdin)["data"]["activeTargets"]
print("  targets:",len(t),dict(collections.Counter(x["labels"]["job"] for x in t)))
print("  down:",[x["labels"]["job"] for x in t if x["health"]!="up"] or "无")
'
echo "=== 3. 黑盒探测是否恢复 ==="
curl -s 'http://10.98.134.245:9090/api/v1/query?query=probe_success' | python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("  probe 序列:",len(r),"成功:",sum(1 for x in r if x["value"][1]=="1"))
'
echo "=== 4. Grafana 看板数据源检查（blackbox 看板是否还有数据） ==="
curl -s 'http://10.98.134.245:9090/api/v1/query?query=count(probe_success)' | head -c 160; echo

