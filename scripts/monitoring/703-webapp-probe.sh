#!/bin/bash
set -uo pipefail
R='--resolve webapp.corp.local:443:192.168.200.210'
echo "=== 从宿主访问 webapp ==="
curl -sk $R -o /dev/null -w '  code=%{http_code}\n' https://webapp.corp.local/
curl -sk $R -D - -o /dev/null https://webapp.corp.local/ | head -6
echo "=== Pod / Service ==="
kubectl -n webapp get pods -o wide --no-headers
kubectl -n webapp get svc --no-headers
echo "=== 网关到 webapp 的转发 ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' | sed -n '/webapp.corp.local/,/}/p' | head -14
echo "=== 黑盒最近一次探测的报错 ==="
kubectl -n monitoring logs deploy/blackbox-exporter --tail=30 | grep -i 'webapp' | tail -5

