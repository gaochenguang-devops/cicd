#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H,json,urllib.error
cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
r=op.open("http://192.168.200.12:30080/auth/login",timeout=60)
print("login ->",r.geturl()[:120])
body=r.read().decode(errors="ignore")
# dex connector link
m=re.search(r'href="([^"]*dex/auth/[^"]*connector_id=keycloak[^"]*)"',body) or re.search(r'href="([^"]*connector_id=keycloak[^"]*)"',body)
if m:
    u=H.unescape(m.group(1))
    if u.startswith("/"): u="http://192.168.200.12:30080"+u
    print("connector ->",u[:110])
    kc=op.open(u,timeout=60)
    act=H.unescape(re.search(r'id="kc-form-login"[^>]*action="([^"]+)"',kc.read().decode(errors="ignore")).group(1))
    resp=op.open(urllib.request.Request(act,data=urllib.parse.urlencode({"username":"dev01","password":"__LDAP_USER_INIT_PASS__"}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST"),timeout=90)
    print("after kc:",resp.status,resp.geturl()[:110])
else:
    print("no connector link; body snippet:",re.sub(r"<[^>]+>"," ",body)[:300])
try:
    x=op.open("http://192.168.200.12:30080/api/v1/applications",timeout=30); print("APPS OK",x.status,x.read()[:120])
except urllib.error.HTTPError as e: print("apps err",e.code,e.read()[:160])
PY
