#!/bin/bash
set -uo pipefail
echo "=== 临时把 speaker 日志提到 debug（定位 shouldAnnounce 决策） ==="
kubectl -n metallb-system patch ds speaker --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--port=7472","--log-level=debug"]}]'
kubectl -n metallb-system rollout status ds/speaker --timeout=120s
sleep 3
# 触发一次 service 重新评估
kubectl -n gateway annotate svc gateway metallb.probe=1 --overwrite >/dev/null
sleep 8
echo "=== 与本节点/VIP 相关的 debug 决策 ==="
kubectl -n metallb-system logs ds/speaker 2>&1 | grep -iE 'shouldAnnounce|announc|notOwner|owner|210|eligible|excluded' | grep -v ServiceReconciler | tail -25
echo "=== ServiceL2Status（有则说明认领成功） ==="
kubectl get servicel2status -A 2>&1 | head -5
