#!/bin/bash
set -uo pipefail

echo "=== 0. keycloak Service selector ==="
kubectl -n keycloak get svc keycloak -o jsonpath='{.spec.selector}{"\n"}'

echo "=== 1. blackbox-exporter + keycloak-metrics Service ==="
kubectl apply -f /root/gw-manifests/monitoring-50-blackbox.yaml
kubectl apply -f /root/gw-manifests/monitoring-52-keycloak-metrics-svc.yaml
kubectl -n monitoring rollout status deploy/blackbox-exporter --timeout=90s | tail -1
kubectl -n kube-system get endpoints keycloak-metrics -o wide 2>/dev/null | tail -1

echo "=== 2. 从 grafana.com 拉官方看板并规范化（datasource uid=prom-main） ==="
mkdir -p /root/grafana-dash/normalized
for id in 15757 1860 13332 13659; do
  [ -s /root/grafana-dash/$id.json ] || curl -s -L -m 40 -o /root/grafana-dash/$id.json "https://grafana.com/api/dashboards/$id/revisions/latest/download"
done
python3 - <<'PY'
import json, os
name_map = {
 "15757": "15757-kubernetes-views-global.json",
 "1860":  "1860-node-exporter-full.json",
 "13332": "13332-kube-state-metrics-v2.json",
 "13659": "13659-blackbox-http-prober.json",
}
outdir="/root/grafana-dash/normalized"
os.makedirs(outdir, exist_ok=True)
for i,f in name_map.items():
    d=json.load(open(f"/root/grafana-dash/{i}.json"))
    d.pop("__inputs", None); d.pop("__requires", None)
    s=json.dumps(d, ensure_ascii=False)
    s=s.replace("${DS_PROMETHEUS}","prom-main").replace("${VAR_DATASOURCE}","prom-main").replace("$DS_PROMETHEUS","prom-main")
    d=json.loads(s)
    def walk(o):
        if isinstance(o, dict):
            ds=o.get("datasource")
            if isinstance(ds, dict) and str(ds.get("uid")) in ("${DS_PROMETHEUS}","prom-main"):
                ds["uid"]="prom-main"
            for v in list(o.values()): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(d)
    json.dump(d, open(f"{outdir}/{f}","w"), ensure_ascii=False, indent=1)
    print("  ", f, "|", d.get("title"), "|", os.path.getsize(f"{outdir}/{f}"), "B")
PY

echo "=== 3. 生成 dashboards ConfigMap ==="
kubectl -n monitoring create cm grafana-dashboards --from-file=/root/grafana-dash/normalized \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null && echo "  CM 已写入"
kubectl -n monitoring get cm grafana-dashboards -o json | python3 -c 'import sys,json;print("  keys:",list(json.load(sys.stdin)["data"].keys()))'

echo "=== 4. 部署 Grafana ==="
kubectl apply -f /root/gw-manifests/monitoring-51-grafana.yaml
kubectl -n monitoring rollout status deploy/grafana --timeout=150s | tail -1
kubectl -n monitoring get pods -l app=grafana -o wide --no-headers
kubectl -n monitoring get svc grafana blackbox-exporter --no-headers
echo "=== grafana ClusterIP ==="
kubectl -n monitoring get svc grafana -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}{"\n"}'
echo "=== Grafana 健康检查（Pod 内） ==="
kubectl -n monitoring exec deploy/grafana -- curl -s -o /dev/null -w '  /api/health -> %{http_code}\n' localhost:3000/api/health 2>/dev/null || \
  kubectl -n monitoring get pod -l app=grafana -o jsonpath='{.items[0].status.podIP}{"\n"}'

