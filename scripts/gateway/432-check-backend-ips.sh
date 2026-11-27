#!/bin/bash
set -uo pipefail
# 网关后端 IP 漂移检查：Service 重建后 ClusterIP 会变，此脚本对比 nginx.conf 与实际 ClusterIP
CONF=/tmp/gw-nginx.conf
kubectl -n gateway get cm gateway-nginx-conf -o jsonpath='{.data.nginx\.conf}' > $CONF

check() {  # $1=域名  $2=svc  $3=namespace(可选)
  local want_have
  want=$(grep -A0 "server_name $1;" -A20 $CONF | grep -m1 'set \$backend' | awk '{print $3}')
  live=$(kubectl -n "${3:-}" get svc "$2" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [ -z "$live" ]; then echo "  SKIP $1 (svc $2 不存在)"; return; fi
  if echo "$want" | grep -q "^$live:"; then echo "  OK   $1 -> $want"; else echo "  DRIFT $1: 配置 $want / 实际 $live"; fi
}

echo "=== 后端 IP 漂移检查 ==="
check jenkins.corp.local    jenkins             jenkins
check harbor.corp.local     harbor              harbor
check sonar.corp.local      sonarqube           sonar
check artifactory.corp.local artifactory-router artifactory
check argocd.corp.local     argocd-server       argocd
check keycloak.corp.local   keycloak            keycloak
check podinfo.corp.local    podinfo             podinfo
check webapp.corp.local     frontend            webapp
check prometheus.corp.local prometheus          monitoring
check alertmanager.corp.local alertmanager      monitoring
