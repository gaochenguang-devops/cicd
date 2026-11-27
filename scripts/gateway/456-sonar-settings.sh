#!/bin/bash
set -uo pipefail
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'curl -s -H "Authorization: Bearer __SONAR_CI_TOKEN__" "http://localhost:9000/api/settings/values"' > /tmp/sonar-settings.json 2>/tmp/sonar-settings.err
echo "  大小: $(wc -c </tmp/sonar-settings.json) bytes"
python3 - <<'EOF'
import json
d=json.load(open("/tmp/sonar-settings.json"))
for s in d.get("settings",[]):
    k=s.get("key","")
    if any(x in k for x in ("oidc","serverBase","auth","sso")):
        print("  ",k,"=",str(s.get("value",s.get("values")))[:120])
EOF
echo "=== 已安装插件里是否有 oidc ==="
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c 'ls /opt/sonarqube/extensions/plugins/' 2>&1 | head -20
