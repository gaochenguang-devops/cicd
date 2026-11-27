#!/bin/bash
set -uo pipefail
echo "=== 网关 error.log 中的 upstream 错误 ==="
kubectl -n gateway logs deploy/gateway --tail=60 | grep -iE 'error|failed|resolve' | tail -12
echo "=== Pod 内 DNS 解析（连续 5 次） ==="
kubectl -n gateway exec deploy/gateway -- sh -c '
for i in 1 2 3 4 5; do
  for h in jenkins.jenkins.svc.cluster.local argocd-server.argocd.svc.cluster.local frontend.webapp.svc.cluster.local alertmanager.monitoring.svc.cluster.local; do
    printf "%s -> %s\n" "$h" "$(nslookup $h 2>/dev/null | awk "/^Name:/{getline; print \$2}")"
  done; echo ---; sleep 1
done'
echo "=== Pod 内直连后端（HTTP 级） ==="
kubectl -n gateway exec deploy/gateway -- sh -c '
for t in jenkins.jenkins:80 argocd-server.argocd:80 frontend.webapp:80 alertmanager.monitoring:9093; do
  printf "  %-40s %s\n" "$t" "$(curl -s -o /dev/null -m 5 -w "%{http_code}" http://$t/)"
done'
echo "=== 再来一轮外部复测 ==="
VIP=192.168.200.210; AUTH='monitoring:__GATEWAY_BASIC_PASS__'
for h in jenkins argocd podinfo alertmanager; do
  printf "  %-12s %s\n" "$h" "$(curl -s -k -o /dev/null -m 10 -w '%{http_code}' -u "$AUTH" --resolve $h.corp.local:443:$VIP https://$h.corp.local/)"
done
echo "=== kube-dns Pod 状态 ==="
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
