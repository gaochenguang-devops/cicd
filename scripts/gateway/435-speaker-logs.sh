#!/bin/bash
set -uo pipefail
echo "=== speaker 全量日志（末 60 行） ==="
kubectl -n metallb-system logs ds/speaker --tail=60 2>&1
echo "=== controller 日志（末 20 行） ==="
kubectl -n metallb-system logs deploy/controller --tail=20 2>&1
echo "=== Service 注解 / 状态 ==="
kubectl -n gateway get svc gateway -o jsonpath='{.metadata.annotations}{"\n"}{.status.loadBalancer}{"\n"}'
echo "=== 是否有 iptables 抢答（kube-proxy 对 VIP 的处理） ==="
iptables -t nat -S OUTPUT 2>/dev/null | grep 192.168.200.210 || echo "  OUTPUT 无 VIP 规则"
iptables -t nat -L KUBE-SERVICES -n 2>/dev/null | grep 192.168.200.210 || echo "  KUBE-SERVICES 无 VIP 规则"
echo "=== speaker 是否真的在监听 ARP 相关（看进程/抓包） ==="
timeout 12 tcpdump -i ens160 -n arp 2>/dev/null | grep -m6 '192.168.200.210' &
sleep 1
arping -c 2 -I ens160 192.168.200.210 >/dev/null 2>&1 || true
wait
echo "=== MetalLB 相关事件 ==="
kubectl -n metallb-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -8
