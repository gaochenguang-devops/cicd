#!/bin/bash
set -uo pipefail

echo "=== 1. 恢复备份规则 ==="
python3 - <<'PY'
import json, subprocess
cm = json.loads(subprocess.check_output(["kubectl","-n","monitoring","get","cm","prometheus-rules","-o","json"]).decode())
base = open("/root/grafana-dash/corp-rules.backup.yml").read()
cm["data"]["corp-rules.yml"] = base.rstrip("\n") + "\n"
for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
    cm["metadata"].pop(k, None)
cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration", None)
json.dump(cm, open("/tmp/rules-base.json","w"))
print("  备份已回写（%d 组）" % base.count("- name: corp-"))
PY
kubectl replace -f /tmp/rules-base.json --force | tail -1

echo "=== 2. 以正确缩进追加自检组（groups 层 2 空格 / rule 层 4 空格） ==="
python3 - <<'PY'
import json, subprocess
cm = json.loads(subprocess.check_output(["kubectl","-n","monitoring","get","cm","prometheus-rules","-o","json"]).decode())
y = cm["data"]["corp-rules.yml"]
block = """  - name: corp-selftest
    rules:
      - alert: SelfTestRule
        expr: vector(1)
        for: 1m
        labels: {severity: warning, test: "true"}
        annotations:
          summary: "告警链路自检（会自动恢复）"
          description: "临时注入，验证 Prometheus 规则 → Alertmanager → bridge → 钉钉群 全链路；测试完由 617 脚本删除。"
"""
cm["data"]["corp-rules.yml"] = y.rstrip("\n") + "\n" + block
for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
    cm["metadata"].pop(k, None)
cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration", None)
json.dump(cm, open("/tmp/rules-selftest2.json","w"))
print("  已追加 corp-selftest")
PY
kubectl replace -f /tmp/rules-selftest2.json --force | tail -1

echo "=== 3. 等 CM 同步到 Pod 后热加载 ==="
sleep 50
kubectl -n monitoring exec deploy/prometheus -- promtool check rules /etc/prometheus/rules/corp-rules.yml 2>&1 | tail -3
kubectl -n monitoring exec deploy/grafana -- curl -s -m 10 -X POST -o /dev/null -w '  reload -> %{http_code}\n' http://prometheus.monitoring.svc.cluster.local:9090/-/reload
sleep 8
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  组数:",len(g),"规则数:",sum(len(x["rules"]) for x in g))
print("  自检组:", [r["name"] for r in g for x in [r] for r in x["rules"] if x["name"]=="SelfTestRule"] if any(r["name"]=="corp-selftest" for r in g) else "未加载")
'
echo "=== 4. 等 for:1m + group_wait 30s ==="
sleep 95
echo "--- AM ---"
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d: print("  ",a["labels"]["alertname"],a["labels"].get("severity"),a["status"]["state"])
print("  共",len(d))
'
echo "--- bridge ---"
kubectl -n monitoring logs -l app=dingtalk-bridge --tail=3 2>&1 | tail -3

echo "=== 5. 清理：移除自检组并热加载 ==="
kubectl replace -f /tmp/rules-base.json --force | tail -1
sleep 45
kubectl -n monitoring exec deploy/grafana -- curl -s -m 10 -X POST -o /dev/null -w '  reload -> %{http_code}\n' http://prometheus.monitoring.svc.cluster.local:9090/-/reload
sleep 8
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  清理后组数:",len(g),"规则数:",sum(len(x["rules"]) for x in g))
'

