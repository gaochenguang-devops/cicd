#!/bin/bash
set -uo pipefail

echo "=== 0. 现状快照 ==="
kubectl -n monitoring get cm prometheus-rules dingtalk-bridge-src 2>/dev/null | tail -2 || echo "  (新 CM 尚未存在，正常)"

echo "=== 1. 应用规则 CM（14 条规则 / 5 组） ==="
kubectl apply -f /root/gw-manifests/monitoring-31-corp-rules.yaml
echo "=== 2. 应用钉钉桥接 ==="
kubectl apply -f /root/gw-manifests/monitoring-43-dingtalk-bridge.yaml
kubectl -n monitoring rollout status deploy/dingtalk-bridge --timeout=90s | tail -1

echo "=== 3. 应用 Alertmanager 路由 ==="
kubectl apply -f /root/gw-manifests/monitoring-40-alertmanager.yaml
kubectl -n monitoring rollout restart deploy/alertmanager >/dev/null
kubectl -n monitoring rollout status deploy/alertmanager --timeout=90s | tail -1

echo "=== 4. Prometheus 换挂载（规则改为独立 CM） ==="
kubectl apply -f /root/gw-manifests/monitoring-30-prometheus.yaml | tail -3
kubectl -n monitoring rollout status deploy/prometheus --timeout=150s | tail -1

echo "=== 5. 规则是否加载 ==="
sleep 5
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' -o /tmp/rules.json
python3 - <<'PY'
import json
d = json.load(open("/tmp/rules.json"))["data"]["groups"]
total = 0
for g in d:
    rs = g["rules"]
    total += len(rs)
    print("  %-22s %d 条：%s" % (g["name"], len(rs), ", ".join(r["name"] for r in rs)))
print("  合计:", total, "条")
PY

echo "=== 6. Alertmanager 是否加载新路由 ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 config show 2>/dev/null | sed -n '1,12p'
kubectl -n monitoring logs deploy/alertmanager --tail=6 2>&1 | tail -6

echo "=== 7. bridge 健康 ==="
kubectl -n monitoring get pods -l app=dingtalk-bridge -o wide --no-headers
kubectl -n monitoring exec deploy/dingtalk-bridge -- python -c 'import urllib.request;print(urllib.request.urlopen("http://localhost:8080/healthz").read().decode())' 2>&1 | tail -2

