#!/bin/bash
set -uo pipefail
echo "=== 崩溃原因确认 ==="
kubectl -n monitoring logs prometheus-8574d65b44-57rrw --previous 2>/dev/null | tail -6 || true
echo "=== 删掉持锁的旧 Pod（单节点 + hostPath，RWO 语义需先腾出锁） ==="
kubectl -n monitoring delete pod prometheus-8558db44dc-rmxpz --force --grace-period=0
sleep 5
kubectl -n monitoring rollout status deploy/prometheus --timeout=150s
kubectl -n monitoring get pods -l app=prometheus -o wide
echo "=== 启动日志尾部 ==="
kubectl -n monitoring logs deploy/prometheus --tail=8 | grep -iE 'error|rules|ready|Server is ready' | tail -4
