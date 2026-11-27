#!/usr/bin/env bash
set -uo pipefail
echo "== 节点/版本 =="
kubectl get node -o custom-columns='NAME:.metadata.name,VER:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage,CRI:.status.nodeInfo.containerRuntimeVersion,RUNTIME:.status.nodeInfo.kernelVersion'
echo "客户端 kubectl: $(kubectl version --client=true -o yaml 2>/dev/null | grep gitVersion | head -1)"
echo
echo "== ArgoCD policy =="
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}' 2>/dev/null || echo "(no rbac cm)"
echo
echo "== Jenkins JCasC 摘要 =="
kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml\.d}' 2>/dev/null | grep -nE 'securityRealm|oidc|ldap|authorizationStrategy|globalMatrix|groups|admin|url' | head -40
echo
echo "== GitLab 认证配置 =="
grep -nE "omniauth|openid_connect|ldap_servers|gitlab_rails\['ldap|allow_single_sign_up|auto_link" /etc/gitlab/gitlab.rb | head -30
echo
echo "== Harbor OIDC 配置 =="
kubectl -n harbor get cm -o name | head -10
kubectl -n harbor get secret -o name | head -10
echo
echo "== Keycloak LDAP 组件 =="
TOK=$(curl -s -X POST 'http://127.0.0.1:30087/realms/master/protocol/openid-connect/token' -d 'client_id=admin-cli' -d 'username=admin' -d 'password=__KEYCLOAK_ADMIN_PASS__' -d 'grant_type=password' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOK" 'http://127.0.0.1:30087/admin/realms/corp/components?type=org.keycloak.storage.UserStorageProvider' | python3 -c '
import sys,json
for c in json.load(sys.stdin):
  print(" ", c["name"], c["providerId"], {k:v for k,v in (c.get("config") or {}).items() if k in ("enabled","connectionUrl","usersDn","bindDn","editMode")})'
