#!/bin/bash
set -uo pipefail
echo "=== CM 里 job 数（应为 9：prometheus/ksm/node-exporter/argocd×3/grafana/keycloak/blackbox-http） ==="
kubectl -n monitoring get cm prometheus-config -o jsonpath='{.data.prometheus\.yml}' | grep -c 'job_name:'
echo "=== Pod 内文件 job 数 ==="
kubectl -n monitoring exec deploy/prometheus -- grep -c 'job_name:' /etc/prometheus/prometheus.yml 2>/dev/null || echo "  grep 不可用"
echo "=== 重启 Prometheus（Recreate） ==="
kubectl -n monitoring rollout restart deploy/prometheus >/dev/null
kubectl -n monitoring rollout status deploy/prometheus --timeout=150s | tail -1
sleep 20
echo "=== 目标数 ==="
curl -s http://10.98.134.245:9090/api/v1/targets?state=active | python3 -c '
import sys,json,collections
t=json.load(sys.stdin)["data"]["activeTargets"]
print("  targets:",len(t),dict(collections.Counter(x["labels"]["job"] for x in t)))
print("  down:",[x["labels"]["job"]+"@"+x["labels"].get("instance","") for x in t if x["health"]!="up"] or "无")
'
echo "=== probe_success ==="
curl -s 'http://10.98.134.245:9090/api/v1/query?query=probe_success' | python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("  序列:",len(r),"成功:",sum(1 for x in r if x["value"][1]=="1"))
'

