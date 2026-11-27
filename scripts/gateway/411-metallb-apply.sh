#!/bin/bash
set -uo pipefail
cd /root
sed -e 's#quay.io/metallb/controller:v0.14.9#192.168.200.12:30090/library/metallb-controller:v0.14.9#' \
    -e 's#quay.io/metallb/speaker:v0.14.9#192.168.200.12:30090/library/metallb-speaker:v0.14.9#' \
    metallb-native.yaml > metallb-native-harbor.yaml
grep -n 'image:' metallb-native-harbor.yaml
kubectl apply -f metallb-native-harbor.yaml 2>&1 | tail -5

cat <<'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: corp-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.200.200-192.168.200.215
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: corp-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - corp-pool
EOF

echo "=== 等待 metallb 就绪 ==="
kubectl -n metallb-system rollout status deploy/metallb-controller --timeout=180s
kubectl -n metallb-system get pods -o wide
echo "=== speaker 日志尾部（是否宣告地址） ==="
kubectl -n metallb-system logs ds/metallb-speaker --tail=15 2>/dev/null | tail -15
