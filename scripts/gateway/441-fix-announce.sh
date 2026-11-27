#!/bin/bash
set -uo pipefail
echo "=== 节点上的相关 label / taint ==="
kubectl get node pxe-boot-test-1 -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep -E 'exclude-from-external-load-balancers|hostname|control-plane'
echo "=== taints ==="
kubectl get node pxe-boot-test-1 -o jsonpath='{.spec.taints}'; echo

echo "=== 方案B：给 L2Advertisement 显式加 nodeSelectors（选中本节点） ==="
cat >/tmp/corp-l2.yaml <<'EOF'
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: corp-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - corp-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: pxe-boot-test-1
EOF
kubectl apply -f /tmp/corp-l2.yaml
sleep 6
echo "--- 决策日志（新增部分） ---"
kubectl -n metallb-system logs ds/speaker 2>&1 | grep -i 'should announce l2' | grep 'gateway' | tail -4
echo "--- ServiceL2Status ---"
kubectl get servicel2status -A 2>&1 | head -5
echo "=== 若方案B无效，则退到方案A：摘掉 exclude-from-external-load-balancers 标签 ==="
if kubectl get servicel2status -A 2>/dev/null | grep -q gateway; then
  echo "  方案B 生效"
else
  echo "  方案B 未生效，执行方案A"
  kubectl label node pxe-boot-test-1 node.kubernetes.io/exclude-from-external-load-balancers-
  sleep 8
  kubectl -n metallb-system logs ds/speaker 2>&1 | grep -i 'should announce l2' | grep 'gateway' | tail -3
  kubectl get servicel2status -A 2>&1 | head -5
fi
echo "=== 恢复 speaker 日志级别 info ==="
kubectl -n metallb-system patch ds speaker --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--port=7472","--log-level=info"]}]' >/dev/null
kubectl -n metallb-system rollout status ds/speaker --timeout=120s | tail -1
echo "=== 节点侧 ARP 检查（.210 是否进入 neighbour 表 / 是否被本机占用） ==="
ip neigh show | grep -E '192.168.200.21' || echo "  无"
