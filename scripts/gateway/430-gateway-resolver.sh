#!/bin/bash
set -uo pipefail
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'

echo "=== 应用新配置（resolver + 变量式 proxy_pass，后端缺失不再 [emerg]） ==="
kubectl apply -f /root/gw-manifests/20-nginx-config.yaml
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=150s

echo "=== nginx -t 配置校验（容器内） ==="
kubectl -n gateway exec deploy/gateway -- nginx -t 2>&1 | tail -2

echo "=== 12 域名复测（无 basic auth 头，模拟真实用户） ==="
for h in gitlab jenkins harbor sonar artifactory argocd keycloak ldapadmin podinfo webapp; do
  code=$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' --resolve $h.corp.local:443:$VIP https://$h.corp.local/)
  printf "  %-14s %s\n" "$h" "$code"
done
for h in prometheus alertmanager; do
  code=$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' -u "$AUTH" --resolve $h.corp.local:443:$VIP https://$h.corp.local/)
  printf "  %-14s %s (ba)\n" "$h" "$code"
done

echo "=== 清理旧 CrashLooping 告警（Prometheus 重启导致的残留） ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 alert resolve \
  alertname="PodCrashLooping" pod="prometheus-8574d65b44-57rrw" 2>&1 | tail -1 || true

echo "=== 网关重启计数（应稳定在重启前的值，不再增长） ==="
kubectl -n gateway get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
