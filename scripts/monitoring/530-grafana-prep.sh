#!/bin/bash
set -uo pipefail
echo "=== ns monitoring 现有资源 ==="
kubectl -n monitoring get deploy,sts,ds,svc,cm,pvc,secret --no-headers 2>/dev/null | awk '{print "  ",$0}'
echo "=== Prometheus 抓取 job 全量 ==="
kubectl -n monitoring get cm prometheus-config -o jsonpath='{.data.prometheus\.yml}' | grep -nE "^  - job_name|targets:" | head -40
echo "=== Harbor 里是否已有 grafana / blackbox 镜像 ==="
for r in library/grafana library/blackbox-exporter library/kube-state-metrics; do
  code=$(curl -s -k -o /dev/null -w '%{http_code}' -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects/library/repositories/${r#library/}/artifacts")
  echo "  $r -> $code"
done
echo "=== 宿主能否访问 grafana.com（取 dashboard API） ==="
curl -s -o /dev/null -w '  grafana.com/api -> %{http_code} %{time_total}s\n' -m 15 "https://grafana.com/api/dashboards/1860/revisions/latest"
curl -s -m 15 "https://grafana.com/api/dashboards/1860/revisions/latest" | head -c 120; echo
echo "=== 可用镜像源探测 ==="
curl -s -o /dev/null -w '  docker.m.daocloud.io -> %{http_code}\n' -m 10 "https://docker.m.daocloud.io/v2/"
echo "=== Jenkins Prometheus 插件 ==="
kubectl -n jenkins exec deploy/jenkins -c jenkins -- sh -c 'ls /var/jenkins_home/plugins 2>/dev/null | grep -i prometheus' || echo "  无 prometheus 插件"
echo "=== Keycloak metrics 开关 ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -c 'import sys,json;[print("  ",e.get("name"),"=",e.get("value")) for e in json.load(sys.stdin)]' 2>/dev/null | head -20

