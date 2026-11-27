#!/usr/bin/env bash
# 部署 Keycloak（K8s）+ Postgres，NodePort 30087
export KUBECONFIG=/root/.kube/config
set -uo pipefail

echo "== 目录与权限 =="
mkdir -p /data/keycloak/pg /data/keycloak/kc
chown -R 999:999 /data/keycloak/pg
chmod 700 /data/keycloak/pg
ls -ld /data/keycloak/*

echo "== 拉取凭据 =="
kubectl get ns keycloak >/dev/null 2>&1 || kubectl create ns keycloak
kubectl -n podinfo get secret harbor-regcred -o yaml \
 | sed -e 's/namespace: podinfo/namespace: keycloak/' \
       -e '/resourceVersion:/d' -e '/uid:/d' -e '/creationTimestamp:/d' \
 | kubectl -n keycloak apply -f - >/dev/null 2>&1
kubectl -n keycloak get secret harbor-regcred --no-headers

echo "== 应用清单 =="
kubectl apply -f /root/keycloak-manifests/00-base.yaml
kubectl apply -f /root/keycloak-manifests/10-deployment.yaml

echo "== 等待就绪（最多 5 分钟）=="
for i in $(seq 1 60); do
  ready=$(kubectl -n keycloak get pod -l app=keycloak -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  phase=$(kubectl -n keycloak get pod -l app=keycloak -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  echo "  [$i] keycloak=${phase:-none}/${ready:-none}"
  [ "$ready" = "true" ] && break
  [ "$phase" = "Failed" ] && { kubectl -n keycloak logs deploy/keycloak --tail=40; exit 1; }
  sleep 5
done

echo "== 状态 =="
kubectl -n keycloak get pod,svc,pvc
echo "== 健康 =="
curl -s -o /dev/null -w '  master realm HTTP %{http_code}\n' http://127.0.0.1:30087/realms/master
kubectl -n keycloak logs deploy/keycloak --tail=25 | grep -Ei 'started|Listening|error|warn' | tail -12
