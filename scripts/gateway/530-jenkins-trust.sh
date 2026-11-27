#!/bin/bash
set -uo pipefail
P=$(kubectl -n jenkins get pod -o name | head -1)
echo "=== Jenkins 容器内解析 harbor.corp.local ==="
kubectl -n jenkins exec $P -c jenkins -- getent hosts harbor.corp.local || echo "  解析失败"
echo "=== Jenkins 容器内 curl https（系统 CA 是否认内部 CA） ==="
kubectl -n jenkins exec $P -c jenkins -- curl -s -o /dev/null -w '  系统CA: %{http_code}\n' https://harbor.corp.local/api/v2.0/systeminfo -m 10 2>&1 | tail -2
echo "=== JVM 是否信任内部 CA ==="
kubectl -n jenkins exec $P -c jenkins -- sh -c 'keytool -list -cacerts -storepass changeit 2>/dev/null | grep -ci "corp internal"' 2>&1 | tail -2
