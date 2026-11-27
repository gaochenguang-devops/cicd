#!/bin/bash
set -uo pipefail
VIP=192.168.200.210
echo "=== 80 -> 443 跳转 ==="
curl -s -o /dev/null -k -w '  http_code=%{http_code} redirect=%{redirect_url}\n' \
  --resolve harbor.corp.local:80:$VIP -H 'Host: harbor.corp.local' "http://$VIP/"

echo "=== 各域名 HTTPS 状态 ==="
for h in gitlab jenkins harbor sonar artifactory argocd keycloak ldapadmin podinfo webapp; do
  out=$(curl -s -k -m 12 -o /tmp/body.$$ -w '%{http_code} %{size_download}' \
        --resolve $h.corp.local:443:$VIP "https://$h.corp.local/" 2>/dev/null)
  title=$(grep -o -m1 '<title>[^<]*' /tmp/body.$$ 2>/dev/null | sed 's/<title>//')
  printf "  %-16s %-10s %s\n" "$h.corp.local" "$out" "$title"
done
rm -f /tmp/body.$$

echo "=== 证书链校验（用内部 CA 验） ==="
echo | openssl s_client -connect $VIP:443 -servername jenkins.corp.local -CAfile /root/gateway-tls/ca.crt 2>/dev/null \
  | grep -E 'Verify return code|subject=' | head -3
echo "=== 未知域名应被 421 拒绝 ==="
curl -s -o /dev/null -k -w '  unknown=%{http_code}\n' --resolve nope.corp.local:443:$VIP https://nope.corp.local/
echo "=== 网关日志（搜索反代错误） ==="
kubectl -n gateway logs deploy/gateway --tail=20 2>&1 | tail -12
