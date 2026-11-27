#!/bin/bash
set -uo pipefail
H='-k --resolve harbor.corp.local:443:192.168.200.210'

echo "=== A. 网关域名（server_name 数量） ==="
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' | grep -c 'server_name .*corp.local'
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' | grep -o 'server_name [a-z]*\.corp\.local' | sed 's/server_name //' | tr '\n' ' '; echo

echo "=== B. NodePort 服务清单 ==="
kubectl get svc -A -o json | python3 -c '
import sys,json
for s in json.load(sys.stdin)["items"]:
    for p in s["spec"]["ports"]:
        if p.get("nodePort"):
            print("  %-12s %-28s %s:%s -> %s" % (s["metadata"]["namespace"], s["metadata"]["name"], p.get("port"), p["nodePort"], p.get("targetPort")))
'

echo "=== C. Prometheus 目标与规则 ==="
curl -s http://10.98.134.245:9090/api/v1/targets?state=active | python3 -c '
import sys,json,collections
t=json.load(sys.stdin)["data"]["activeTargets"]
print("  targets:",len(t),dict(collections.Counter(x["labels"]["job"] for x in t)))
print("  down:",[x["labels"]["job"] for x in t if x["health"]!="up"] or "无")
'
curl -s 'http://10.98.134.245:9090/api/v1/rules?type=alert' | python3 -c '
import sys,json
g=json.load(sys.stdin)["data"]["groups"]
print("  规则:",sum(len(x["rules"]) for x in g),"条 /",len(g),"组:",[(x["name"],len(x["rules"])) for x in g])
'

echo "=== D. Alertmanager 路由 receiver ==="
kubectl -n monitoring exec deploy/alertmanager -- amtool --alertmanager.url=http://localhost:9093 config show 2>/dev/null | sed -n '/^route:/,/^inhibit_rules:/p' | grep -E 'receiver|group_wait|repeat_interval' | head -8

echo "=== E. Harbor：EXT_ENDPOINT 与实际访问方式 ==="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
echo -n "  http://192.168.200.12:30090/api/v2.0/systeminfo -> "
curl -s -o /dev/null -w '%{http_code}\n' -u 'admin:__HARBOR_ADMIN_PASS__' http://192.168.200.12:30090/api/v2.0/systeminfo
echo -n "  https://harbor.corp.local/api/v2.0/systeminfo -> "
curl -s $H -o /dev/null -w '%{http_code}\n' -u 'admin:__HARBOR_ADMIN_PASS__' https://harbor.corp.local/api/v2.0/systeminfo

echo "=== F. Keycloak：client 数与 harbor/argocd 回调 ==="
TOK=$(curl -s $H -X POST 'https://keycloak.corp.local/realms/master/protocol/openid-connect/token' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=__KEYCLOAK_ADMIN_PASS__' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s $H -H "Authorization: Bearer $TOK" 'https://keycloak.corp.local/admin/realms/corp/clients' | python3 -c '
import sys,json
d=json.load(sys.stdin)
print("  client 数:",len(d))
for c in d:
    print("   %-14s redirect=%s" % (c["clientId"], c.get("redirectUris")))
'

echo "=== G. 监控工作负载 ==="
kubectl -n monitoring get deploy,ds --no-headers | awk '{print "  "$1,$2,$3,$4}'
echo "=== H. 节点容量 ==="
df -h / | tail -1; free -g | sed -n '2p'; nproc

echo "=== I. 命名空间与 Pod 数 ==="
kubectl get ns --no-headers | awk '{print $1}' | tr '\n' ' '; echo
kubectl get pods -A --no-headers | awk '{print $4}' | sort | uniq -c

echo "=== J. ArgoCD 应用 ==="
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers

