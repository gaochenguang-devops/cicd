#!/bin/bash
set -uo pipefail
echo "=== 现有告警规则（CM prometheus-config: corp-rules.yml） ==="
kubectl -n monitoring get cm prometheus-config -o jsonpath='{.data.corp-rules\.yml}'
echo
echo "=== Alertmanager 配置 ==="
kubectl -n monitoring get cm alertmanager-config -o jsonpath='{.data.alertmanager\.yml}'
echo
echo "=== wechat-bridge 实现（前 120 行） ==="
kubectl -n monitoring get cm wechat-bridge-src -o jsonpath='{.data}' 2>/dev/null | head -c 200
kubectl -n monitoring get deploy wechat-bridge -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{.spec.template.spec.containers[0].command}{"\n"}' 2>/dev/null
echo "=== wechat-bridge ConfigMap 列表 ==="
kubectl -n monitoring get cm | grep -i bridge

