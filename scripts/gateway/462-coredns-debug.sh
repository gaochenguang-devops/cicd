#!/bin/bash
set -uo pipefail
echo "=== coredns 日志 ==="
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20 2>&1 | tail -25
echo "=== 当前 Corefile ==="
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
echo "=== corp.hosts 内容 ==="
kubectl -n kube-system get cm coredns-corp-hosts -o jsonpath='{.data.corp\.hosts}'
