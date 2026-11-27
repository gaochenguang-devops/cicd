#!/bin/bash
set -uo pipefail
echo "=== 回滚 L2Advertisement 到原样（去掉 nodeSelectors，保持通用） ==="
cat >/tmp/corp-l2.yaml <<'EOF'
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: corp-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - corp-pool
EOF
kubectl apply -f /tmp/corp-l2.yaml
sleep 6
echo "=== 宣告状态 ==="
kubectl get l2advertisement -A
kubectl get servicel2status -A
echo "=== 节点 label 现状（应已无 exclude-from-external-load-balancers） ==="
kubectl get node pxe-boot-test-1 -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep -E 'exclude|hostname|control-plane'
echo "=== speaker 规格（日志级别已恢复 info） ==="
kubectl -n metallb-system get ds speaker -o jsonpath='{.spec.template.spec.containers[0].args}'; echo
echo "=== 宿主侧 HTTPS 到 VIP ==="
curl -k -s -o /dev/null -w "  gitlab.corp.local -> %{http_code}\n" --resolve gitlab.corp.local:443:192.168.200.210 https://gitlab.corp.local/ -m 10
curl -k -s -o /dev/null -w "  keycloak.corp.local -> %{http_code}\n" --resolve keycloak.corp.local:443:192.168.200.210 https://keycloak.corp.local/ -m 10
echo "=== 302 跳转目标（待切换 external_url 的证据） ==="
curl -k -s -o /dev/null -D - --resolve gitlab.corp.local:443:192.168.200.210 https://gitlab.corp.local/ -m 10 | grep -i '^location'
curl -k -s -o /dev/null -D - --resolve keycloak.corp.local:443:192.168.200.210 https://keycloak.corp.local/ -m 10 | grep -i '^location'
