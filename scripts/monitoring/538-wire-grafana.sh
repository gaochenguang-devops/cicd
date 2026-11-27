#!/bin/bash
set -uo pipefail

echo "=== 1. Grafana 起来了吗 ==="
kubectl -n monitoring rollout status deploy/grafana --timeout=120s | tail -1
kubectl -n monitoring get pods -l app=grafana -o wide --no-headers
kubectl -n monitoring exec deploy/grafana -- curl -s localhost:3000/api/health 2>/dev/null | head -c 200; echo

echo "=== 2. Prometheus 增加 grafana / keycloak / blackbox 抓取 job ==="
kubectl -n monitoring get cm prometheus-config -o json > /tmp/promcm.json
python3 - <<'PY'
import json
cm=json.load(open("/tmp/promcm.json"))
y=cm["data"]["prometheus.yml"]
if "job_name: blackbox-http" in y:
    print("  已存在，跳过")
else:
    jobs = """
  - job_name: grafana
    static_configs:
      - targets: ['grafana.monitoring.svc.cluster.local:3000']

  - job_name: keycloak
    metrics_path: /metrics
    static_configs:
      - targets: ['keycloak-metrics.keycloak.svc.cluster.local:9000']

  # 黑盒探测：每个对外入口一条 up 指标，覆盖所有服务的可达性
  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://gitlab.corp.local/
          - https://jenkins.corp.local/
          - https://harbor.corp.local/
          - https://sonar.corp.local/
          - https://artifactory.corp.local/
          - https://argocd.corp.local/
          - https://keycloak.corp.local/
          - https://ldapadmin.corp.local/
          - https://podinfo.corp.local/
          - https://webapp.corp.local/
          - https://prometheus.corp.local/
          - https://alertmanager.corp.local/
          - https://grafana.corp.local/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter.monitoring.svc.cluster.local:9115
"""
    marker = "  # 说明（已实测，不要再试）："
    y = y.replace(marker, jobs + "\n" + marker)
    cm["data"]["prometheus.yml"] = y
    for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
        cm["metadata"].pop(k, None)
    cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration",None)
    json.dump(cm, open("/tmp/promcm2.json","w"))
    print("  已生成新配置，字节:", len(y))
PY
if [ -f /tmp/promcm2.json ]; then
  kubectl replace -f /tmp/promcm2.json --force | tail -1
fi
kubectl -n monitoring rollout restart deploy/prometheus >/dev/null
kubectl -n monitoring rollout status deploy/prometheus --timeout=120s | tail -1

echo "=== 3. 网关加 grafana.corp.local（ClusterIP 见上一行输出） ==="
GIP=$(kubectl -n monitoring get svc grafana -o jsonpath='{.spec.clusterIP}')
kubectl -n gateway get cm gateway-nginx-conf -o json > /tmp/gwcm.json
python3 - "$GIP" <<'PY'
import json,sys
gip=sys.argv[1]
cm=json.load(open("/tmp/gwcm.json"))
conf=cm["data"]["nginx.conf"]
if "server_name grafana.corp.local" in conf:
    print("  已存在，跳过")
    sys.exit(0)
block = """    # Grafana 自带登录页，不再叠加网关 Basic Auth
    server {
        listen 443 ssl;
        server_name grafana.corp.local;
        ssl_certificate     /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:SSL:10m;
        set $backend %s:3000;                  # svc grafana.monitoring:3000
        location = /healthz { access_log off; return 200 "ok\\n"; }
        location / { proxy_pass http://$backend; }
    }

""" % gip
marker = "    # 未匹配的域名：明确拒绝"
conf = conf.replace(marker, block + marker)
cm["data"]["nginx.conf"] = conf
for k in ("resourceVersion","uid","creationTimestamp","managedFields"):
    cm["metadata"].pop(k, None)
cm["metadata"].get("annotations",{}).pop("kubectl.kubernetes.io/last-applied-configuration",None)
json.dump(cm, open("/tmp/gwcm2.json","w"))
print("  网关配置已加 grafana server 块，backend=%s:3000" % gip)
PY
kubectl replace -f /tmp/gwcm2.json --force | tail -1
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=120s | tail -1

echo "=== 4. 补 DNS：宿主 hosts + CoreDNS corp 区 ==="
grep -q "grafana.corp.local" /etc/hosts || echo "192.168.200.210 grafana.corp.local" >> /etc/hosts
kubectl -n kube-system get cm coredns-corp-hosts -o jsonpath='{.data.corp\.hosts}' > /tmp/ch.txt
if ! grep -q "grafana.corp.local" /tmp/ch.txt; then
  python3 - <<'PY'
p="/tmp/ch.txt"
line=open(p).read().strip()
line = line + " grafana.corp.local"
open(p,"w").write(line+"\n")
PY
  kubectl -n kube-system create cm coredns-corp-hosts --from-file=corp.hosts=/tmp/ch.txt --save-config=false -o yaml --dry-run=client | grep -v 'creationTimestamp' > /tmp/chcm.yaml
  kubectl -n kube-system replace -f /tmp/chcm.yaml --force | tail -1
fi
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n kube-system rollout status deploy/coredns --timeout=90s | tail -1

echo "=== 5. 复查 ==="
kubectl -n monitoring get pods -o wide --no-headers
echo "--- 域名解析（宿主 & 集群内）"
getent hosts grafana.corp.local
kubectl -n monitoring exec deploy/prometheus -- nslookup grafana.corp.local 2>/dev/null | tail -3 || true

