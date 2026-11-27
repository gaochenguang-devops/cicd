#!/usr/bin/env bash
set -uo pipefail
echo "== 1. webapp 命名空间与拉取凭据 =="
kubectl get ns webapp >/dev/null 2>&1 || kubectl create namespace webapp
U=$(head -1 /root/harbor-ci-creds.txt); S=$(tail -1 /root/harbor-ci-creds.txt)
kubectl -n webapp create secret docker-registry harbor-regcred \
  --docker-server=192.168.200.12:30090 --docker-username="$U" --docker-password="$S" \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tail -1

echo "== 2. 注册 Application =="
kubectl apply -f /tmp/podinfo-src/deploy/webapp/application.yaml 2>&1 | tail -1
kubectl -n argocd annotate application webapp argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
sleep 40
kubectl -n argocd get applications

echo "== 3. 工作负载 =="
kubectl -n webapp get pods -o wide
kubectl -n webapp get svc,hpa 2>/dev/null

echo "== 4. 访问验证 =="
curl -s -m 5 -o /dev/null -w "  frontend /         http=%{http_code}\n" http://192.168.200.12:30096/
curl -s -m 5 -o /dev/null -w "  frontend /healthz  http=%{http_code}\n" http://192.168.200.12:30096/healthz
echo "  前端调用后端 /echo 代理:"
curl -s -m 8 "http://192.168.200.12:30096/echo" -o /tmp/echo.json -w "   http=%{http_code}\n"
head -c 300 /tmp/echo.json 2>/dev/null; echo
echo "  后端直连（集群内 service）:"
kubectl -n webapp run probe-$RANDOM --rm -i --restart=Never --image=192.168.200.12:30090/apps/busybox:v1 -- sh -c 'wget -qO- http://backend:9898/healthz 2>/dev/null || echo "wget 不可用"' 2>/dev/null | tail -3
