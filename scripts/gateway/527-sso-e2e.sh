#!/bin/bash
set -uo pipefail
KP=$(kubectl -n keycloak get pod -o name | grep -v db | grep -v Terminating | head -1)

echo "=== 造一个临时 realm 用户做端到端 SSO 验证 ==="
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1 || exit 1
$KC create users -r corp -s username=sso-probe -s enabled=true -s email=sso-probe@corp.local -s emailVerified=true -s firstName=SSO -s lastName=Probe >/dev/null 2>&1
$KC set-password -r corp --username sso-probe --new-password "SsoProbe@2026" >/dev/null 2>&1 && echo "  用户 sso-probe 已建"
'

cat > /tmp/sso_probe.py <<'PY'
import ssl, sys, urllib.request, urllib.parse, http.cookiejar, re
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
cj = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx), urllib.request.HTTPCookieProcessor(cj))
op.addheaders=[('User-Agent','probe')]

def get(url):
    r = op.open(url, timeout=20)
    return r.geturl(), r.status, r.read().decode('utf-8','ignore')

def login(start, label):
    try:
        final, code, body = get(start)
    except Exception as e:
        print(f"  {label}: 起跳失败 {e}"); return
    if 'Invalid parameter' in body:
        print(f"  {label}: ❌ redirect_uri 仍被拒"); return
    m = re.search(r'action="([^"]+)"', body)
    if not m:
        print(f"  {label}: 没拿到登录表单，停在 {final[:90]}"); return
    action = m.group(1).replace('&amp;','&')
    data = urllib.parse.urlencode({'username':'sso-probe','password':'SsoProbe@2026','credentialId':''}).encode()
    try:
        r = op.open(urllib.request.Request(action, data=data), timeout=25)
        fin, st, b = r.geturl(), r.status, r.read().decode('utf-8','ignore')
    except Exception as e:
        print(f"  {label}: ❌ 提交凭据后出错 {e}"); return
    ok = st == 200 and ('Invalid' not in b[:3000])
    print(f"  {label}: 最终 {st} @ {fin[:110]}")
    print(f"  {label}: cookies = {[c.name for c in cj]}")

login("https://harbor.corp.local/c/oidc/login", "Harbor")
cj.clear()
login("https://argocd.corp.local/auth/login", "ArgoCD")
PY
python3 /tmp/sso_probe.py

echo "=== 清理临时用户 ==="
kubectl -n keycloak exec $KP -- /bin/sh -c '
KC=/opt/keycloak/bin/kcadm.sh
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "__KEYCLOAK_ADMIN_PASS__" >/dev/null 2>&1
ID=$($KC get users -r corp -q username=sso-probe --fields id --format csv --noquotes | tail -1)
[ -n "$ID" ] && $KC delete users/$ID -r corp >/dev/null 2>&1 && echo "  临时用户已删除"
'
