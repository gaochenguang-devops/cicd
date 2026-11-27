#!/bin/bash
set -uo pipefail
echo "=== ServiceL2Status（speaker 是否把 VIP 认领到本节点） ==="
kubectl get servicel2statuses -A 2>/dev/null || kubectl get servicel2status -A 2>/dev/null || echo "  CRD 不存在/查询失败"
echo "=== 地址池状态 ==="
kubectl -n metallb-system get ipaddresspool corp-pool -o jsonpath='{.status.conditions[*].type}{" "}{.status.conditions[*].status}{"\n"}'
echo "=== excludel2 配置 ==="
kubectl -n metallb-system get cm metallb-excludel2 -o jsonpath='{.data}' | head -c 400; echo
echo "=== 对照实验：临时 LB Service 拿 .211，看是否 ARP 应答 ==="
kubectl -n gateway delete svc arp-probe --ignore-not-found >/dev/null 2>&1
kubectl -n gateway expose deploy gateway --name arp-probe --port 80 --type LoadBalancer >/dev/null 2>&1
kubectl -n gateway annotate svc arp-probe metallb.universe.tf/loadBalancerIPs=192.168.200.211 --overwrite >/dev/null
sleep 6
kubectl -n gateway get svc arp-probe
echo "--- arping .211 ---"
arping -c 3 -I ens160 192.168.200.211 2>&1 | tail -3
echo "--- 对照 arping .12（节点自身，应该有应答） ---"
arping -c 2 -I ens160 192.168.200.12 2>&1 | tail -3
echo "=== 清理 ==="
kubectl -n gateway delete svc arp-probe --ignore-not-found >/dev/null 2>&1 && echo "  arp-probe 已删除"
