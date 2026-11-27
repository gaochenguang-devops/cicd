#!/bin/bash
set -uo pipefail
echo "=== 网关 Service（VIP/端口） ==="
kubectl -n gateway get svc gateway -o wide --no-headers
echo "=== 各服务 ClusterIP ==="
kubectl get svc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,CLUSTERIP:.spec.clusterIP,PORTS:.spec.ports[*].port,EXTIP:.spec.externalIPs --no-headers | grep -vE "kube-system/(kube-dns|kubelet)" | head -40
echo "=== Runner 配置（宿主 systemd） ==="
grep -E "^url|executor|concurrent" /etc/gitlab-runner/config.toml 2>/dev/null | head -10
echo "=== containerd 自定义 registry 配置 ==="
for d in /etc/containerd/certs.d/*/; do echo "--- $d"; cat "$d/hosts.toml" 2>/dev/null | sed 's/^/    /'; done
echo "=== ArgoCD 轮询间隔 / webhook 配置 ==="
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.timeout\.reconciliation}{"\n"}{.data.webhook\.github}{"\n"}' 2>/dev/null
kubectl -n argocd get cm argocd-cm -o yaml | grep -iE "reconciliation|webhook|statusbadge" | head -5
echo "=== Prometheus 抓取目标 ==="
kubectl -n monitoring get cm prometheus-config -o jsonpath='{.data.prometheus\.yml}' 2>/dev/null | grep -E "job_name|targets" -A2 | head -30
echo "=== /etc/hosts 里 corp.local 条目数 ==="
grep -c "corp.local" /etc/hosts
echo "=== CoreDNS 权威区 ==="
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | sed -n '1,40p'

