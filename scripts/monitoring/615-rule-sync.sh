#!/bin/bash
set -uo pipefail
echo "=== pod 内规则文件是否已更新（kubelet 同步 CM 有延迟） ==="
kubectl -n monitoring exec deploy/prometheus -- cat /etc/prometheus/rules/corp-rules.yml 2>/dev/null | tail -12
echo "=== 组内文件是否含 SelfTestRule ==="
kubectl -n monitoring exec deploy/prometheus -- grep -c SelfTestRule /etc/prometheus/rules/corp-rules.yml 2>/dev/null || echo "  0（文件还没同步过来）"
echo "=== CM 里确认有 ==="
kubectl -n monitoring get cm prometheus-rules -o jsonpath='{.data.corp-rules\.yml}' | grep -c SelfTestRule
echo "=== 等 45s 让 kubelet 把 CM 同步到 Pod ==="
sleep 45
kubectl -n monitoring exec deploy/prometheus -- grep -c SelfTestRule /etc/prometheus/rules/corp-rules.yml 2>/dev/null || echo "  仍未同步"
echo "=== 再次热加载 ==="
kubectl -n monitoring exec deploy/grafana -- curl -s -m 10 -X POST -o /dev/null -w '  reload -> %{http_code}\n' http://prometheus.monitoring.svc.cluster.local:9090/-/reload
sleep 8
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  组数:",len(g),"规则数:",sum(len(x["rules"]) for x in g))
for x in g:
    if "selftest" in x["name"]: print("  自检组已加载:", [r["name"] for r in x["rules"]])
'

