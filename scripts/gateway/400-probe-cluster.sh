#!/bin/bash
set -uo pipefail
echo "=== 节点与 IP ==="
kubectl get nodes -o wide
ip -4 addr show | grep -E 'inet ' | grep -v 127.0.0.1
echo "=== 现有 LB / Gateway 相关 ==="
kubectl get ns | awk '{print $1}' | tr '\n' ' '; echo
kubectl get crd 2>/dev/null | grep -iE 'metallb|gateway|nginx' || echo "  无 metallb/gateway CRD"
kubectl get pods -A -o wide | awk 'NR==1{print $1,$2,$3,$7} NR>1{print $1,$2,$3,$7}' | head -40
echo "=== service 类型统计 ==="
kubectl get svc -A | awk 'NR>1{print $3}' | sort | uniq -c
echo "=== 资源 ==="
free -g | head -2; df -h / /data | tail -2
echo "=== 192.168.200.200-215 是否被占用（ping） ==="
for i in 200 201 202 203 204 205 210 215; do
  ping -c1 -W1 192.168.200.$i >/dev/null 2>&1 && echo "  .$i 有响应" || echo "  .$i 空闲"
done
echo "=== 本机 /etc/hosts 与 VM 网络 ==="
cat /etc/hosts | head -10
echo "=== 集群 API 上的 service CIDR / kube-proxy 模式 ==="
kubectl -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' 2>/dev/null | grep -E 'mode|clusterCIDR' || echo "  读不到 kube-proxy 配置"
