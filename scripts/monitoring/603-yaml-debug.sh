#!/bin/bash
set -uo pipefail
echo "=== 43 文件头 14 行（含不可见字符） ==="
sed -n '1,14p' /root/gw-manifests/monitoring-43-dingtalk-bridge.yaml | cat -A | cut -c1-160
echo "=== 40 文件 65~75 行 ==="
sed -n '60,75p' /root/gw-manifests/monitoring-40-alertmanager.yaml | cat -A | cut -c1-160
echo "=== python 解析试错 ==="
python3 -c "
import yaml,sys
for f in ['/root/gw-manifests/monitoring-43-dingtalk-bridge.yaml','/root/gw-manifests/monitoring-40-alertmanager.yaml']:
    try:
        list(yaml.safe_load_all(open(f)))
        print('  OK', f)
    except Exception as e:
        print('  FAIL', f, e)
"
echo "=== 当前 CM 实际内容对比 ==="
kubectl -n monitoring get cm alertmanager-config -o jsonpath='{.data.alertmanager\.yml}' | grep -n 'dingtalk' | head -5

