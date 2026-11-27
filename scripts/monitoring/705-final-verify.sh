#!/bin/bash
set -uo pipefail
echo "=== 目标 / 规则 / 黑盒 ==="
curl -s http://10.98.134.245:9090/api/v1/targets?state=active | python3 -c '
import sys,json
t=json.load(sys.stdin)["data"]["activeTargets"]
print("  targets:",len(t),"down:",[x["labels"].get("instance") for x in t if x["health"]!="up"] or "无")'
curl -s http://10.98.134.245:9090/api/v1/rules?type=alert | python3 -c '
import sys,json;g=json.load(sys.stdin)["data"]["groups"];print("  规则:",sum(len(x["rules"]) for x in g),"条 /",len(g),"组")'
curl -s 'http://10.98.134.245:9090/api/v1/query?query=probe_success' | python3 -c '
import sys,json;r=json.load(sys.stdin)["data"]["result"];print("  probe:",len(r),"条，成功",sum(1 for x in r if x["value"][1]=="1"))'
echo "=== Grafana 看板 ==="
kubectl -n monitoring exec deploy/grafana -- curl -s -u 'admin:__GRAFANA_ADMIN_PASS__' 'http://localhost:3000/api/search?type=dash-db' 2>/dev/null | python3 -c '
import sys,json
d=json.load(sys.stdin);print("  dashboards:",len(d));[print("   -",x["title"]) for x in d]' 2>/dev/null || echo "  (grafana api 取不到)"
echo "=== 钉钉桥健康 ==="
kubectl -n monitoring exec deploy/dingtalk-bridge -- wget -qO- http://localhost:8080/healthz 2>/dev/null; echo

