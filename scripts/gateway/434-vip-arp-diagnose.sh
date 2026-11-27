#!/bin/bash
set -uo pipefail
echo "=== 1. 节点网卡与路由 ==="
ip -br addr
ip route
echo "=== 2. MetalLB Pod / Speaker 日志（找 210 的宣告与报错） ==="
kubectl -n metallb-system get pods -o wide
kubectl -n metallb-system logs ds/speaker --tail=30 2>&1 | grep -iE '210|announc|arp|error|fail|interface' | tail -15 || true
echo "=== 3. Speaker 启动参数（是否带 --interface） ==="
kubectl -n metallb-system get ds speaker -o jsonpath='{.spec.template.spec.containers[0].args}' ; echo
echo "=== 4. 服务端点是否就绪（L2 宣告不看 endpoints，但排障要知道） ==="
kubectl -n gateway get endpoints gateway
echo "=== 5. 宿主上用 arping 测 .210（同机自发自答，验证 speaker 是否在该网卡回应） ==="
command -v arping >/dev/null || dnf -q -y install iputils >/dev/null 2>&1
IFACE=$(ip -o -4 addr show | awk '/192\.168\.200\.12/{print $2}')
echo "  测试网卡: $IFACE"
arping -c 3 -I "$IFACE" 192.168.200.210 2>&1 | tail -4 || true
echo "=== 6. 宿主自身访问 VIP ==="
curl -s -o /dev/null -k -m 8 -w '  VIP:443 = %{http_code}\n' https://192.168.200.210/ || echo "  连接失败"
echo "=== 7. ARP 表里 .210 是否有条目 ==="
ip neigh show | grep 192.168.200.210 || echo "  无邻居条目"
