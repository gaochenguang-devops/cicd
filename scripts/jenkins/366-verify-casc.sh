#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
echo "=== whoAmI ==="; curl -s -u "$AU" "$J/whoAmI/api/json" | head -c 200; echo
echo "=== credentials ==="; curl -s -u "$AU" "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName]" | head -c 900; echo
echo "=== 启动日志 ==="
kubectl -n jenkins logs deploy/jenkins --tail=60 | grep -iE 'casc|library|credential|SEVERE|BootFailure' | tail -12
