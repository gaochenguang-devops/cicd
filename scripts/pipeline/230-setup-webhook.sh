#!/usr/bin/env bash
set -uo pipefail
H="PRIVATE-TOKEN: __GITLAB_PAT__"
P="http://127.0.0.1/api/v4/projects/2"
URL="http://192.168.200.12:30080/api/webhook"

echo "===== 1. 现有 hook ====="
curl -s -H "$H" "$P/hooks" | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  (none)" if not d else "\n".join("  %s push=%s"%(h["url"],h.get("push_events")) for h in d))'

echo "===== 2. 注册（只订阅 push，不做 SSL 校验）====="
curl -s -H "$H" -X POST "$P/hooks" \
  --data-urlencode "url=$URL" \
  --data "push_events=true&enable_ssl_verification=false&tag_push_events=false" \
| python3 -c 'import json,sys;d=json.load(sys.stdin);print("  id=%s url=%s push=%s"%(d.get("id"),d.get("url"),d.get("push_events")))'

echo "===== 3. 触发一次测试推送 ====="
ID=$(curl -s -H "$H" "$P/hooks" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["id"])')
curl -s -o /dev/null -w "  test hook http=%{http_code}\n" -H "$H" -X POST "$P/hooks/$ID/test"

echo "===== 4. ArgoCD server 日志是否收到 webhook ====="
sleep 3
kubectl -n argocd logs deploy/argocd-server --tail=20 | grep -iE 'webhook|refresh' | tail -6 | sed 's/^/  /'

echo "===== 5. ArgoCD 侧 webhook 相关配置（是否设了 secret）====="
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data}' | python3 -c '
import json,sys,base64
d=json.load(sys.stdin)
for k in d:
    if "webhook" in k: print("  key=%s len=%s"%(k, len(base64.b64decode(d[k]))))
print("  (未设置任何 webhook secret，即免签名)" if not any("webhook" in k for k in d) else "")
'
