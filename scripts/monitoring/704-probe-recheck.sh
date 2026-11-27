#!/bin/bash
set -uo pipefail
sleep 45
echo "=== 目标健康 ==="
curl -s http://10.98.134.245:9090/api/v1/targets?state=active | python3 -c '
import sys,json
t=json.load(sys.stdin)["data"]["activeTargets"]
bad=[(x["labels"].get("instance"),x["lastError"]) for x in t if x["health"]!="up"]
print("  total:",len(t),"up:",len(t)-len(bad))
for i,e in bad: print("   DOWN",i,"|",e[:160])
'
echo "=== probe_success ==="
curl -s 'http://10.98.134.245:9090/api/v1/query?query=probe_success' | python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("  序列:",len(r),"成功:",sum(1 for x in r if x["value"][1]=="1"),
      "失败:",[x["metric"]["instance"] for x in r if x["value"][1]=="0"])
'
echo "=== 容器内探测 webapp ==="
kubectl -n monitoring exec deploy/blackbox-exporter -- /bin/sh -c '
wget -qO- --no-check-certificate "http://localhost:9115/probe?target=https://webapp.corp.local/&module=http_2xx" 2>/dev/null | grep -E "probe_success|probe_http_status_code|probe_duration" | head -3
' 2>/dev/null || echo "  (wget 不可用)"

