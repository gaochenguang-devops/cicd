#!/bin/bash
set -uo pipefail
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'

echo "=== 1. 应用 ClusterIP 版配置 ==="
kubectl apply -f /root/gw-manifests/20-nginx-config.yaml
kubectl -n gateway rollout restart deploy/gateway >/dev/null
kubectl -n gateway rollout status deploy/gateway --timeout=150s
kubectl -n gateway exec deploy/gateway -- nginx -t 2>&1 | tail -1

echo "=== 2. IP 漂移检查 ==="
bash /root/gw-manifests/check-backend-ips.sh 2>/dev/null || true

echo "=== 3. 12 域名复测（无鉴权头） ==="
for h in gitlab jenkins harbor sonar artifactory argocd keycloak ldapadmin podinfo webapp; do
  printf "  %-13s %s\n" "$h" "$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' --resolve $h.corp.local:443:$VIP https://$h.corp.local/)"
done
for h in prometheus alertmanager; do
  printf "  %-13s %s (ba)\n" "$h" "$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' -u "$AUTH" --resolve $h.corp.local:443:$VIP https://$h.corp.local/)"
done

echo "=== 4. 网关错误日志（应无 502/无 emerge） ==="
kubectl -n gateway logs deploy/gateway --tail=40 | grep -iE 'emerg|502|prematurely|failed' | tail -5 || echo "  无错误"
kubectl -n gateway get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount'
