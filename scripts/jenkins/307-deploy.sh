#!/usr/bin/env bash
# 在 192.168.200.12 部署 Jenkins（K8s 单节点 + hostPath 持久化 + LDAP 统一认证）
export KUBECONFIG=/root/.kube/config
set -uo pipefail

echo "== 0. 宿主机目录 =="
mkdir -p /data/jenkins
chown -R 1000:1000 /data/jenkins
ls -ld /data/jenkins

echo "== 1. 命名空间 + 拉取凭据 =="
kubectl get ns jenkins >/dev/null 2>&1 || kubectl create ns jenkins
kubectl -n podinfo get secret harbor-regcred -o yaml \
 | sed -e 's/namespace: podinfo/namespace: jenkins/' \
       -e '/resourceVersion:/d' -e '/uid:/d' -e '/creationTimestamp:/d' \
 | kubectl -n jenkins apply -f - >/dev/null 2>&1
kubectl -n jenkins get secret harbor-regcred

echo "== 2. LDAP 管理员密码 Secret =="
kubectl -n jenkins create secret generic jenkins-ldap \
  --from-literal=manager-password='__LDAP_ADMIN_PASS__' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n jenkins get secret jenkins-ldap

echo "== 3. 应用清单（PV/PVC/ConfigMap/Deployment/Service）=="
kubectl apply -f /root/jenkins-manifests/00-base.yaml
kubectl apply -f /root/jenkins-manifests/10-deployment.yaml

echo "== 4. 等待启动（最多 8 分钟，首次要下载插件）=="
for i in $(seq 1 96); do
  phase=$(kubectl -n jenkins get pod -l app=jenkins -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  ready=$(kubectl -n jenkins get pod -l app=jenkins -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  echo "  [$i] phase=${phase:-none} ready=${ready:-none}"
  if [ "$ready" = "true" ]; then break; fi
  if [ "$phase" = "Failed" ]; then kubectl -n jenkins describe pod -l app=jenkins | tail -30; exit 1; fi
  sleep 5
done

echo "== 5. 状态 =="
kubectl -n jenkins get pod,svc,pvc
kubectl -n jenkins logs deploy/jenkins --tail=40 | grep -Ei 'Jenkins is fully|ERROR|WARN|Configuration as Code|LDAP' | tail -20
