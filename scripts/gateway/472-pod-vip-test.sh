#!/bin/bash
set -uo pipefail
CIP=$(kubectl -n gateway get svc gateway -o jsonpath='{.spec.clusterIP}')
VIP=$(kubectl -n gateway get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "gateway ClusterIP=$CIP  VIP=$VIP"
NP=$(kubectl -n podinfo get pod -o name | head -1)
echo "=== Pod → VIP（当前 DNS 结果） ==="
kubectl -n podinfo exec $NP -- sh -c "curl -sk -m 8 -o /dev/null -w '  vip   -> %{http_code}\n' https://keycloak.corp.local/realms/corp/../../../health/ready" 2>&1 | tail -2
echo "=== Pod → ClusterIP ==="
kubectl -n podinfo exec $NP -- sh -c "curl -sk -m 8 -o /dev/null -w '  cip   -> %{http_code}\n' --resolve keycloak.corp.local:443:$CIP https://keycloak.corp.local/realms/corp/.well-known/openid-configuration" 2>&1 | tail -2

echo "=== 清理 Keycloak 重复的 KC_HOSTNAME（只保留 https 那条） ==="
kubectl -n keycloak get deploy keycloak -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
env=d["spec"]["template"]["spec"]["containers"][0]["env"]
keep=[e for e in env if e["name"]!="KC_HOSTNAME"]
keep.append({"name":"KC_HOSTNAME","value":"https://keycloak.corp.local"})
d["spec"]["template"]["spec"]["containers"][0]["env"]=keep
print(json.dumps(d))
' > /tmp/kc.json
kubectl replace -f /tmp/kc.json --force | tail -1
kubectl -n keycloak get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -c KC_HOSTNAME
