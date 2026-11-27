#!/usr/bin/env bash
set -uo pipefail
echo "===== 版本 ====="
kubectl version --short 2>/dev/null | head -3
cat /etc/rocky-release 2>/dev/null | head -2
echo
echo "===== Harbor 仓库列表 ====="
for p in apps library; do
  curl -s -u admin:'__HARBOR_ADMIN_PASS__' "http://127.0.0.1:30090/api/v2.0/projects/$p/repositories?page_size=50" \
   | python3 -c "import sys,json
for r in json.load(sys.stdin): print('  $p/'+r['name'].split('/')[-1], r.get('artifact_count'))"
done
echo
echo "===== Runner 配置 ====="
sed -n '1,60p' /etc/gitlab-runner/config.toml 2>/dev/null | grep -E 'name|url|executor|concurrent|privileged|tag|limit' || true
grep -E '^concurrent' /etc/gitlab-runner/config.toml 2>/dev/null || true
echo
echo "===== ArgoCD RBAC / dex ====="
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.policy\.csv}' 2>/dev/null | head -20
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}' 2>/dev/null | head -30
echo
echo "===== ArgoCD 应用 targetRevision/namespace ====="
kubectl -n argocd get application -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.destination.namespace}{" "}{.spec.source.targetRevision}{" "}{.spec.source.path}{"\n"}{end}'
echo
echo "===== Jenkins 关键配置 ====="
kubectl -n jenkins get cm -o name 2>/dev/null
curl -s -o /dev/null -w 'jenkins=%{http_code}\n' http://127.0.0.1:30088/login
echo
echo "===== 数据目录 ====="
du -sh /data/* 2>/dev/null | sort -h | tail -15
echo
echo "===== 计划任务 / timer ====="
systemctl list-timers --no-pager --no-legend 2>/dev/null | head -6
