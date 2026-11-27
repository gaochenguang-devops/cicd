#!/bin/bash
set -uo pipefail
CA=/root/gateway-tls/ca.crt

echo "===== A. 撤掉 jenkins/sonar 上坏掉的 java-cacerts 挂载（先解除阻塞） ====="
for pair in "jenkins jenkins" "sonar sonarqube"; do
  set -- $pair; NS=$1; DN=$2
  kubectl -n $NS get deploy $DN -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
t=d["spec"]["template"]["spec"]
t["volumes"]=[v for v in t.get("volumes",[]) if v["name"]!="java-cacerts"]
for c in t["containers"]:
    c["volumeMounts"]=[m for m in c.get("volumeMounts",[]) if m["name"]!="java-cacerts"]
print(json.dumps(d))
' > /tmp/${DN}.json
  kubectl replace -f /tmp/${DN}.json --force 2>&1 | tail -1
done

echo "===== B. CoreDNS 挂载修正：改为目录挂载 + 改 Corefile 路径 ====="
kubectl -n kube-system get deploy coredns -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
c=d["spec"]["template"]["spec"]["containers"][0]
for m in c["volumeMounts"]:
    if m["name"]=="corp-hosts":
        m["mountPath"]="/etc/coredns-extra"
        m.pop("subPath",None)
print(json.dumps(d))
' > /tmp/coredns.json
kubectl replace -f /tmp/coredns.json --force 2>&1 | tail -1

kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | sed 's#/etc/coredns/corp.hosts#/etc/coredns-extra/corp.hosts#' > /tmp/Corefile.fix
kubectl -n kube-system create cm coredns --from-file=Corefile=/tmp/Corefile.fix --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1
sleep 25
kubectl -n kube-system get pods -l k8s-app=kube-dns
echo "--- 集群内解析验证 ---"
P=$(kubectl -n sonar get pod -o name | grep sonarqube | head -1)
kubectl -n sonar exec $P -c sonarqube -- getent hosts keycloak.corp.local 2>&1 | head -2 || true
P2=$(kubectl -n harbor get pod -o name | grep harbor-core | head -1)
kubectl -n harbor exec $P2 -c core -- getent hosts gitlab.corp.local 2>&1 | head -2 || true
