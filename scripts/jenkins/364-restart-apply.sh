#!/bin/bash
set -uo pipefail
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
echo "=== 校验 YAML 语法 ==="
kubectl -n jenkins exec $POD -- bash -lc 'python3 -c "import yaml,sys; d=yaml.safe_load(open(\"/var/jenkins_home/casc/jenkins.yaml\")); print(\"keys:\", list(d.keys())); print(\"creds ids:\", [c.get(\"id\") or list(c.values())[0].get(\"id\") for c in d[\"jenkins\"][\"credentials\"][\"system\"][\"domainCredentials\"][0][\"credentials\"]]); print(\"libs:\", [l[\"name\"] for l in d[\"unclassified\"][\"globalLibraries\"][\"libraries\"]])" 2>&1 | head -8'

echo "=== 重启 Jenkins 让 JCasC 全量应用 ==="
kubectl -n jenkins rollout restart deploy/jenkins
kubectl -n jenkins rollout status deploy/jenkins --timeout=180s
sleep 15
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
echo "=== whoAmI ==="; curl -s -u "$AU" "$J/whoAmI/api/json" | head -c 200; echo
echo "=== credentials ==="; curl -s -u "$AU" "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName]" | head -c 800; echo
echo "=== 启动日志中的 casc 结果 ==="
NEWPOD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')
kubectl -n jenkins logs $NEWPOD --tail=200 | grep -iE 'casc|Did not find|credential|library|SEVERE|WARN' | tail -15
