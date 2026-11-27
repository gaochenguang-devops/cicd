#!/bin/bash
set -uo pipefail

echo "=== 1. 备份当前规则并追加一条自检规则（expr=vector(1)，必定触发） ==="
kubectl -n monitoring get cm prometheus-rules -o jsonpath='{.data.corp-rules\.yml}' > /root/grafana-dash/corp-rules.backup.yml
python3 - <<'PY'
import json, subprocess
cm = json.loads(subprocess.check_output(["kubectl","-n","monitoring","get","cm","prometheus-rules","-o","json"]).decode())
y = cm["data"]["corp-rules.yml"]
if "SelfTestRule" in y:
    print("  已存在，跳过")
else:
    y += """
      - name: corp-selftest
        rules:
          - alert: SelfTestRule
            expr: vector(1)
            for: 1m
            labels: {severity: warning, test: "true"}
            annotations:
              summary: "告警链路自检（自动恢复）"
              description: "由 614 脚本临时注入，验证 Prometheus 规则 → Alertmanager → bridge → 钉钉群；10 分钟后脚本自动删除本条规则。"
"""
    cm["data"]["corp-rules.yml"] = y
    for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
        cm["metadata"].pop(k, None)
    cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration", None)
    json.dump(cm, open("/tmp/rules-selftest.json","w"))
    print("  已生成带自检规则的 CM")
PY
if [ -f /tmp/rules-selftest.json ]; then kubectl replace -f /tmp/rules-selftest.json --force | tail -1; fi

echo "=== 2. 热加载 Prometheus（--web.enable-lifecycle 已开） ==="
kubectl -n monitoring exec deploy/grafana -- curl -s -m 10 -X POST -o /dev/null -w '  reload -> %{http_code}\n' http://prometheus.monitoring.svc.cluster.local:9090/-/reload
sleep 10
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  组数:",len(g),"规则数:",sum(len(x["rules"]) for x in g))
print("  自检规则:", [r["name"] for x in g for r in x["rules"] if r["name"]=="SelfTestRule"] or "尚未加载")
'

echo "=== 3. 等 for:1m + group_wait 30s，看是否进钉钉 ==="
sleep 100
echo "--- AM 侧 ---"
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  ",a["labels"]["alertname"],a["labels"].get("severity"),a["status"]["state"])
print("  共",len(d))
'
echo "--- bridge 侧 ---"
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=5 2>&1 | tail -5
