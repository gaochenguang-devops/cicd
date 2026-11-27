#!/bin/bash
set -uo pipefail
echo "=== 1. 集群内 DNS + 端口：从 grafana Pod 里访问 grafana.corp.local ==="
kubectl -n monitoring exec deploy/grafana -- curl -s -o /dev/null -w '  in-cluster https://grafana.corp.local/login -> %{http_code}\n' https://grafana.corp.local/login 2>&1 | tail -2

echo "=== 2. 宿主经 VIP + Host 头 ==="
curl -s -k -o /dev/null -w '  VIP(Host: grafana) /login -> %{http_code}\n' -H "Host: grafana.corp.local" https://192.168.200.210/login
curl -s -k -o /dev/null -w '  VIP(Host: grafana) /api/health -> %{http_code}\n' -H "Host: grafana.corp.local" https://192.168.200.210/api/health

echo "=== 3. Prometheus 抓取结果 ==="
curl -s 'http://10.98.134.245:9090/api/v1/targets?state=active' -o /tmp/tg.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/tg.json"))["data"]["activeTargets"]
print("  活跃 target 总数:", len(d))
ok=[];bad=[]
for t in d:
    (ok if t["health"]=="up" else bad).append("%s [%s]" % (t["labels"].get("job"), t["scrapeUrl"].split("/")[-1]))
from collections import Counter
print("  按 job:", dict(Counter(t["labels"].get("job") for t in d)))
print("  DOWN:", bad if bad else "无")
for t in d:
    if t["labels"].get("job")=="blackbox-http":
        print("   probe %-40s -> %s" % (t["labels"].get("instance"), t["health"]))
PY

echo "=== 4. Grafana 里看板是否加载 ==="
curl -s -u 'admin:__GRAFANA_ADMIN_PASS__' 'http://10.106.157.157:3000/api/search?type=dash-db' -o /tmp/gs.json
python3 - <<'PY'
import json
try:
    d=json.load(open("/tmp/gs.json"))
    for x in d: print("   %-45s uid=%s folder=%s" % (x["title"], x["uid"], x.get("folderTitle")))
except Exception as e:
    print("   解析失败:", e, open("/tmp/gs.json").read()[:200])
PY
echo "=== 5. Grafana 抓取指标（Prometheus 里 grafana_build_info 是否存在） ==="
curl -s 'http://10.98.134.245:9090/api/v1/query?query=up{job=~"grafana|keycloak"}' | head -c 400; echo

