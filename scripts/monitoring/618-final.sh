#!/bin/bash
set -uo pipefail
echo "=== 最终状态 ==="
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  规则组:",len(g),"规则数:",sum(len(x["rules"]) for x in g))
'
curl -s http://10.103.87.112:9093/api/v2/alerts | python3 -c '
import sys,json
d=json.load(sys.stdin)
print("  AM 告警:",len(d),[a["labels"]["alertname"]+"("+a["status"]["state"]+")" for a in d])
'
echo "  bridge 投递成功次数:" $(kubectl -n monitoring logs -l app=dingtalk-bridge 2>&1 | grep -c 'errcode":0')
kubectl -n monitoring get pods -l app=dingtalk-bridge --no-headers

