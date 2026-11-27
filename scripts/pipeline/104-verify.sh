#!/usr/bin/env bash
set -uo pipefail
GL="http://192.168.200.12"; PAT="__GITLAB_PAT__"
cd /tmp/podinfo-src && git fetch -q origin main
CODE_COMMIT=$(git log origin/main --invert-grep --grep='\[skip ci\]' -1 --format='%H')
echo "最近一次代码提交：${CODE_COMMIT:0:8}  $(git log -1 --format=%s "$CODE_COMMIT")"
PIPE=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines?sha=$CODE_COMMIT" | jq -r '.[0].id // empty')
echo "对应流水线 #$PIPE"
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE" | jq -r '"  status=\(.status) created=\(.created_at) updated=\(.updated_at)"'
curl -s -H "PRIVATE-TOKEN: $PAT" "$GL/api/v4/projects/2/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name) \(.status) \((.duration // 0)|floor)s"'
echo
echo "== Harbor 镜像 tag 列表 =="
curl -s -u "admin:__HARBOR_ADMIN_PASS__" "$GL:30090/api/v2.0/projects/apps/repositories/podinfo/artifacts?page_size=6&sort=push_time" \
  | jq -r '.[] | "  \(.tags[0].name)  \(.size/1048576|floor)MB  \(.push_time)"'
echo
echo "== 集群当前状态 =="
kubectl -n podinfo get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,IMAGE:.spec.containers[0].image
echo
kubectl -n argocd get app podinfo -o jsonpath='ArgoCD: {.status.sync.status}/{.status.health.status} rev={.status.sync.revision}{"\n"}'
curl -s -m 5 http://192.168.200.12:30095/version
echo
echo "== 全链路资源清单 =="
kubectl -n podinfo get all,hpa,pdb,networkpolicy,configmap,sa -o name 2>/dev/null | sed 's/^/  /'
