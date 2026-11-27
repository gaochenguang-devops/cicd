#!/bin/bash
kubectl -n monitoring exec deploy/dingtalk-bridge -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8080/healthz').read().decode())"
echo "--- 最近 bridge 日志 ---"
kubectl -n monitoring logs deploy/dingtalk-bridge --tail=6 | sed 's/^/  /'

