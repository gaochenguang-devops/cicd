#!/bin/bash
set -uo pipefail
echo "=== Harbor 项目是否 public ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects?page_size=20' \
 | python3 -c 'import sys,json
for p in json.load(sys.stdin): print("  ",p["name"],"public=",p.get("metadata",{}).get("public"))'

echo "=== 各 Service 端口（ClusterIP 视角） ==="
kubectl get svc -A -o json | python3 -c '
import sys,json
d=json.load(sys.stdin)
for s in d["items"]:
    m=s["metadata"]; sp=s["spec"]
    ports=",".join(f"{p.get(\"name\",\"-\")}:{p[\"port\"]}->{p.get(\"targetPort\")}" for p in sp.get("ports",[]))
    print(f"  {m[\"namespace\"]}/{m[\"name\"]} type={sp.get(\"type\")} clusterIP={sp.get(\"clusterIP\")} ports={ports}")'

echo "=== GitHub 可达（取 gateway-api CRD 用） ==="
curl -s -o /dev/null -m 10 -w '  github=%{http_code}\n' https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest
curl -s -o /dev/null -m 10 -w '  raw.githubusercontent=%{http_code}\n' https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/standard-install.yaml

echo "=== 现有 imagePullSecrets ==="
kubectl get secrets -A 2>/dev/null | grep -iE 'regcred|harbor' || echo "  none"
kubectl -n library get secrets 2>/dev/null | head -3
