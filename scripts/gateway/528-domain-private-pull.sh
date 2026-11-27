#!/bin/bash
set -uo pipefail
U='robot$apps+ci-builder'; P='__HARBOR_ROBOT_CI_SECRET__'
echo "=== 私有项目用域名拉（kubelet 路径，带 secret 里的凭据） ==="
crictl pull --creds "$U:$P" harbor.corp.local/apps/redis:7-alpine 2>&1 | tail -2
echo
echo "=== Jenkins 共享库/流水线里的 registry 引用 ==="
grep -rn "192.168.200.12:30090" /var/lib/jenkins-shared-library 2>/dev/null | head -8
curl -s -k -H "PRIVATE-TOKEN: __GITLAB_PAT__" "https://gitlab.corp.local/api/v4/projects/3/repository/files/src%2Fcom%2Fcorp%2Fplatform%2FDefaults.groovy/raw?ref=main" | grep -n "192.168.200.12:30090"
