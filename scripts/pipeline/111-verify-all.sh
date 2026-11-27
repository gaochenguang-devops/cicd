#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
echo "===== 1. 组件存活 ====="
printf "  GitLab   : "; curl -s -o /dev/null -w "%{http_code}\n" "$GL/users/sign_in"
printf "  Harbor   : "; curl -s -o /dev/null -w "%{http_code}\n" "$GL:30090/api/v2.0/systeminfo"
printf "  ArgoCD   : "; curl -s -o /dev/null -w "%{http_code}\n" "$GL:30080/"
printf "  Runner   : "; systemctl is-active gitlab-runner
printf "  Containerd: "; systemctl is-active containerd

echo
echo "===== 2. ArgoCD 应用 ====="
kubectl -n argocd get applications

echo
echo "===== 3. 工作负载 ====="
kubectl -n podinfo get deploy,hpa,pdb -o wide 2>/dev/null | head -8
echo
kubectl -n webapp get deploy,hpa 2>/dev/null

echo
echo "===== 4. 服务可用性 ====="
printf "  podinfo /version : "; curl -s -m 5 "$GL:30095/version" | tr -d '\n' ; echo
printf "  podinfo /healthz : "; curl -s -o /dev/null -w "%{http_code}\n" -m 5 "$GL:30095/healthz"
printf "  webapp  /        : "; curl -s -o /dev/null -w "%{http_code}\n" -m 5 "$GL:30096/"
printf "  webapp  /echo    : "; curl -s -m 5 -X POST -d '{"msg":"final-check"}' "$GL:30096/echo" | tr -d '\n' | head -c 120; echo

echo
echo "===== 5. Harbor 项目镜像 ====="
for repo in podinfo redis metrics-server busybox; do
  printf "  %-16s " "$repo:"
  curl -s -u "admin:__HARBOR_ADMIN_PASS__" "$GL:30090/api/v2.0/projects/apps/repositories/$repo/artifacts?page_size=9" \
    | jq -r '[.[]?.tags[0].name] | join(", ")' 2>/dev/null || echo "-"
done

echo
echo "===== 6. 最近流水线 ====="
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines?per_page=4" \
  | jq -r '.[] | "  #\(.id) \(.status) \(.sha[0:8]) \(.source)"'

echo
echo "===== 7. 资源占用 ====="
kubectl top node 2>/dev/null | head -2
free -m | sed -n '1,2p'
df -h /data | tail -1
