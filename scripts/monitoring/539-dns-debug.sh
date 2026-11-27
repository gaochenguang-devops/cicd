#!/bin/bash
set -uo pipefail
echo "=== corp.hosts 实际内容 ==="
kubectl -n kube-system get cm coredns-corp-hosts -o jsonpath='{.data.corp\.hosts}' | cat -A | head -3
echo "=== Corefile 里 corp.local 段 ==="
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | sed -n '/corp.local:53/,/^}/p'
echo "=== CoreDNS Pod 挂载 ==="
kubectl -n kube-system get pods -l k8s-app=kube-dns --no-headers
POD=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec $POD -c coredns -- cat /etc/coredns-extra/corp.hosts 2>&1 | head -3
echo "=== 直接 dig（Pod 内） ==="
kubectl -n monitoring exec deploy/prometheus -- cat /etc/resolv.conf | head -3
POD2=$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec $POD2 -c coredns -- nslookup grafana.corp.local 127.0.0.1 2>&1 | tail -4
echo "=== CoreDNS 日志 ==="
kubectl -n kube-system logs $POD -c coredns --tail=10 2>&1 | tail -10

