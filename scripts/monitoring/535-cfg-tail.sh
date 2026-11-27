#!/bin/bash
set -uo pipefail
echo "=== gateway nginx.conf 第 160 行到结尾 ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' | sed -n '160,260p'
echo "=== gateway CM 的 data key 列表 ==="
kubectl -n gateway get cm gateway-nginx-conf -o json | python3 -c 'import sys,json;print(list(json.load(sys.stdin)["data"].keys()))'
echo "=== coredns-corp-hosts 现状 ==="
kubectl -n kube-system get cm coredns-corp-hosts -o jsonpath='{.data.corp\.hosts}'
echo "=== prometheus CM 尾部（插入点） ==="
kubectl -n monitoring get cm prometheus-config -o jsonpath='{.data.prometheus\.yml}' | tail -22
