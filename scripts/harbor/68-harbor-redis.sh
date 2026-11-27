#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== redis pending 原因 =="
kubectl -n harbor describe pod harbor-redis-0 2>/dev/null | sed -n '/Events:/,$p' | head -12
echo "== redis sts 存储配置 =="
kubectl -n harbor get sts harbor-redis -o json | jq -r '.spec.volumeClaimTemplates // "none"'
echo
echo "== chart 中 redis 相关持久化 =="
grep -nE "redis" /tmp/harbor-values.yaml | head -20
echo "---"
awk '/^  persistentVolumeClaim:/{f=1} f&&/^[a-z]/&&!/^  /{f=0} f' /tmp/harbor-values.yaml | grep -nE "redis|database|registry|jobLog|^    [a-z]" | head -20
echo
echo "== harbor 各 pod =="
kubectl -n harbor get pods
echo
echo "== 镜像拉取进度 =="
kubectl -n harbor get events --sort-by=.lastTimestamp 2>/dev/null | grep -E "Pulled|Started|Failed" | tail -8
