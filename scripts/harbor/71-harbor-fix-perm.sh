#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== 各组件运行 UID =="
for p in harbor-database-0 harbor-core-6749ddb7f5-jcfz9 harbor-registry-7cf7884fd7-lpz8w harbor-redis-0 harbor-jobservice-5847d95f7b-c455d; do
  printf "%-40s " "$p"
  kubectl -n harbor get pod "$p" -o jsonpath='{.spec.securityContext.runAsUser}{" / "}{.spec.securityContext.fsGroup}{"\n"}' 2>/dev/null || echo
done
echo
echo "== 修正权限 =="
chown -R 999:999 /data/harbor/database /data/harbor/valkey
chown -R 10000:10000 /data/harbor/registry /data/harbor/joblog
chmod -R u+rwX,g+rwX /data/harbor
stat -c "%U:%G %a %n" /data/harbor/*
echo
echo "== 重建 database =="
kubectl -n harbor delete pod harbor-database-0 --wait=false >/dev/null
sleep 20
kubectl -n harbor get pods
echo
echo "== 等待全部就绪（最多 3 分钟）=="
for i in $(seq 1 36); do
  R=$(kubectl -n harbor get pods --no-headers 2>/dev/null | awk '{print $2}' | grep -cE "^1/1$|^2/2$")
  T=$(kubectl -n harbor get pods --no-headers 2>/dev/null | wc -l)
  [ "$R" = "$T" ] && [ "$T" -ge 6 ] && { echo "  all ready at +$(( i*5 ))s"; break; }
  sleep 5
done
kubectl -n harbor get pods
echo
echo "== API 验证 =="
curl -s -u "admin:__HARBOR_ADMIN_PASS__" -o /tmp/sys.json -w "  systeminfo http=%{http_code}\n" http://192.168.200.12:30090/api/v2.0/systeminfo
jq -r '"  harbor_version=\(.harbor_version) auth=\(.auth_mode) registry=\(.registry_url)"' /tmp/sys.json 2>/dev/null
curl -s -u "admin:__HARBOR_ADMIN_PASS__" -w "\n  projects http=%{http_code}\n" http://192.168.200.12:30090/api/v2.0/projects | tail -2
