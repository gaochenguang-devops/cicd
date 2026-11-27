#!/bin/bash
set -uo pipefail
echo "=== Prometheus 最近 reload 相关日志 ==="
kubectl -n monitoring logs deploy/prometheus --tail=25 2>&1 | grep -iE 'reload|error|rule' | tail -12
echo "=== 直接对容器内文件做 promtool 校验（镜像内自带 promtool） ==="
kubectl -n monitoring exec deploy/prometheus -- promtool check rules /etc/prometheus/rules/corp-rules.yml 2>&1 | tail -12

