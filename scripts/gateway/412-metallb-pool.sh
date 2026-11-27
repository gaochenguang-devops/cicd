#!/bin/bash
set -uo pipefail
echo "=== 等 controller/speaker Ready ==="
kubectl -n metallb-system rollout status deploy/controller --timeout=240s
kubectl -n metallb-system rollout status ds/speaker --timeout=240s
kubectl -n metallb-system get pods -o wide

echo "=== 再建地址池（webhook 已就绪） ==="
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
kubectl -n metallb-system get ipaddresspool,l2advertisement
echo "=== speaker 日志 ==="
kubectl -n metallb-system logs ds/speaker --tail=8
