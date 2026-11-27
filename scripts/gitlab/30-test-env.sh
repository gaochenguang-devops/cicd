#!/usr/bin/env bash
# 测试前置盘点：确认测试所需工具与对象现状
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== binaries =="
for b in kubectl argocd git curl jq base64; do printf "%-8s " "$b"; command -v $b || echo "MISSING"; done
echo
echo "== argocd cli login =="
if command -v argocd >/dev/null; then
  argocd version --client --short 2>&1 | head -2
  argocd app list -n argocd --server 192.168.200.12:30080 --insecure --grpc-web 2>&1 | head -5
fi
echo
echo "== argocd API via curl =="
ADMIN_PW=$(cat /root/.argocd-admin-password 2>/dev/null || echo "")
TOKEN=$(curl -sk -X POST http://192.168.200.12:30080/api/v1/session \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PW\"}" | jq -r '.token // empty')
if [ -n "$TOKEN" ]; then echo "API token OK (${#TOKEN} chars)"; echo "$TOKEN" > /root/.argocd-api-token; else echo "API token FAIL"; fi
echo
echo "== applications =="
curl -sk -H "Authorization: Bearer $TOKEN" "http://192.168.200.12:30080/api/v1/applications" | jq -r '.[] | "\(.metadata.name)\t\(.status.sync.status)\t\(.status.health.status)\t\(.spec.source.repoURL)\t\(.spec.source.path)"'
echo
echo "== gitlab =="
curl -s -o /dev/null -w "gitlab http=%{http_code}\n" http://192.168.200.12/
echo "== repo workdir =="
ls -la /root/work/cicd-demo 2>/dev/null | head -5
cd /root/work/cicd-demo 2>/dev/null && git log --oneline -3 && git remote -v
echo
echo "== argocd app demo-app detail =="
curl -sk -H "Authorization: Bearer $TOKEN" "https://192.168.200.12:30080/api/v1/applications/demo-app" | jq '{sync:.status.sync.status, health:.status.health.status, rev:.status.sync.revision, auto:.spec.syncPolicy, dest:.spec.destination, resources:(.status.resources|length)}'
echo
echo "== mem/cpu =="
free -m | head -2
kubectl top node 2>/dev/null | head -2
echo "== gitlab services =="
gitlab-ctl status 2>/dev/null | head -10
