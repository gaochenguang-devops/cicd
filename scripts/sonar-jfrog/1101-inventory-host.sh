#!/usr/bin/env bash
set -uo pipefail
echo "===== NodePort 明细 ====="
kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.type}{" "}{range .spec.ports[*]}{.port}{"->"}{.nodePort}{" "}{end}{"\n"}{end}' \
 | awk '$3=="NodePort"'
echo
echo "===== ArgoCD Applications ====="
kubectl -n argocd get application -o custom-columns='NAME:.metadata.name,REPO:.spec.source.repoURL,PATH:.spec.source.path,REV:.spec.source.targetRevision,SYNC:.status.sync.status,HEALTH:.status.health.status'
echo
echo "===== 宿主机 systemd 服务 ====="
systemctl list-units --type=service --state=running --no-pager --no-legend | grep -Ei 'gitlab|runner|docker|podman|kubelet|containerd|nginx|ldap' || true
echo
echo "===== Podman 容器（LDAP 等） ====="
podman ps --format '{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}' 2>/dev/null || true
echo
echo "===== 监听端口（关键） ====="
ss -lntp 2>/dev/null | awk 'NR==1 || /:(80|443|22|389|636|8090|8080|300[0-9][0-9]|6443|10250|2375|2376)\s/' | head -40
echo
echo "===== 磁盘 ====="
df -h / /data 2>/dev/null | tail -3
echo
echo "===== 内存 ====="
free -h | head -2
