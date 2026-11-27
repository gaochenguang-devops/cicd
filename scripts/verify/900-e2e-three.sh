#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H,json
KC="http://192.168.200.12:30087"
def kc_login(op,authorize_url,user="dev01",pw="__LDAP_USER_INIT_PASS__"):
    kc=op.open(authorize_url,timeout=60).read().decode(errors="ignore")
    m=re.search(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"',kc)
    if not m: return kc
    act=H.unescape(m.group(1))
    return op.open(urllib.request.Request(act,data=urllib.parse.urlencode({"username":user,"password":pw}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST"),timeout=90).read().decode(errors="ignore")

# ---- ArgoCD
try:
    cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    r=op.open("http://192.168.200.12:30080/auth/login?return_url=%2Fapplications",timeout=60)
    print("argocd login ->",r.geturl()[:90])
    kc_login(op,r.geturl())
    s=json.load(op.open("http://192.168.200.12:30080/api/v1/session",timeout=30))
    print("argocd session:",s.get("loggedIn"),s.get("username"),s.get("userInfo",{}).get("groups"))
except Exception as e: print("argocd ERR:",type(e).__name__,e)

# ---- Jenkins
try:
    cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    r=op.open("http://192.168.200.12:30088/securityRealm/commenceLogin?from=%2F",timeout=60)
    print("jenkins commence ->",r.geturl()[:90])
    kc_login(op,r.geturl())
    w=op.open("http://192.168.200.12:30088/whoAmI/api/json",timeout=30).read().decode()
    d=json.loads(w); print("jenkins whoAmI:",d.get("name"),d.get("authorities"))
except Exception as e: print("jenkins ERR:",type(e).__name__,e)

# ---- Harbor
try:
    cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    r=op.open("http://192.168.200.12:30090/c/oidc/login",timeout=60)
    print("harbor oidc ->",r.geturl()[:90])
    kc_login(op,r.geturl())
    u=json.load(op.open("http://192.168.200.12:30090/api/v2.0/users/current",timeout=30))
    print("harbor current user:",u.get("username"),"admin=",u.get("sysadmin_flag"))
except Exception as e: print("harbor ERR:",type(e).__name__,e)
PY
