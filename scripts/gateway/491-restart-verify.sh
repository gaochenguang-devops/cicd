#!/bin/bash
set -uo pipefail
echo "===== 重启 Sonar 使 serverBaseURL 生效 ====="
kubectl -n sonar rollout restart deploy/sonarqube | tail -1
kubectl -n sonar rollout status deploy/sonarqube --timeout=240s | tail -1
echo "===== Jenkins/ArgoCD/Harbor 状态 ====="
kubectl -n jenkins rollout status deploy/jenkins --timeout=240s | tail -1
kubectl -n argocd get pods | grep -E 'server|dex'
kubectl -n harbor get pods | grep core
sleep 10
echo "===== 站点矩阵（宿主，CA 已信任） ====="
for h in harbor sonar artifactory argocd gitlab keycloak jenkins prometheus alertmanager ldapadmin podinfo webapp; do
  code=$(curl -s -o /dev/null -k -w "%{http_code}" https://$h.corp.local/ -m 15)
  printf "  %-13s %s\n" "$h" "$code"
done
echo "===== 关键跳转目标 ====="
for u in "https://gitlab.corp.local/" "https://keycloak.corp.local/" "https://argocd.corp.local/" "https://sonar.corp.local/" "https://harbor.corp.local/" "https://jenkins.corp.local/"; do
  loc=$(curl -s -o /dev/null -D - -k "$u" -m 15 | grep -i '^location' | head -1 | tr -d '\r')
  printf "  %-34s %s\n" "$u" "$loc"
done
