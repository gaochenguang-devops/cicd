#!/usr/bin/env bash
set -uo pipefail
PAT="__GITLAB_PAT__"
APP_URL="http://192.168.200.12/root/podinfo.git"

echo "== 1. 注册 podinfo 仓库到 ArgoCD =="
kubectl -n argocd create secret generic repo-podinfo \
  --from-literal=type=git --from-literal=url="$APP_URL" \
  --from-literal=username=root --from-literal=password="$PAT" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository --dry-run=client -o yaml \
  | kubectl apply -f - 2>&1 | tail -1

echo "== 2. 创建命名空间 =="
kubectl get ns podinfo >/dev/null 2>&1 || kubectl create namespace podinfo

echo "== 3. 创建镜像拉取凭据 =="
U=$(head -1 /root/harbor-ci-creds.txt); S=$(tail -1 /root/harbor-ci-creds.txt)
kubectl -n podinfo create secret docker-registry harbor-regcred \
  --docker-server=192.168.200.12:30090 --docker-username="$U" --docker-password="$S" \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1

echo "== 4. 应用 ArgoCD Application =="
kubectl apply -f /tmp/podinfo-src/deploy/podinfo/application.yaml 2>&1 | tail -2
sleep 8
kubectl -n argocd get applications podinfo -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision 2>/dev/null

echo "== 5. 手动硬刷新 =="
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null
sleep 25
kubectl -n argocd get applications podinfo -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision

echo "== 6. podinfo 命名空间资源 =="
kubectl -n podinfo get all -o wide 2>/dev/null | head -12
echo
kubectl -n podinfo get pvc,hpa,pdb 2>/dev/null

echo "== 7. 事件（若有 ImagePull 失败）=="
kubectl -n podinfo get events --sort-by=.lastTimestamp 2>/dev/null | tail -6
