#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H,urllib.error
def login(u):
    cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    r=op.open("http://192.168.200.12:30080/auth/login",timeout=60)
    act=H.unescape(re.search(r'id="kc-form-login"[^>]*action="([^"]+)"',r.read().decode(errors="ignore")).group(1))
    op.open(urllib.request.Request(act,data=urllib.parse.urlencode({"username":u,"password":"__LDAP_USER_INIT_PASS__"}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST"),timeout=90)
    return op
for u in ["dev01","qa01","lead01","ops01"]:
    op=login(u)
    req=urllib.request.Request("http://192.168.200.12:30080/api/v1/projects/rbac-probe",method="DELETE",headers={"Content-Type":"application/json"})
    try: print(u,"->",op.open(req,timeout=30).status)
    except urllib.error.HTTPError as e: print(u,"->",e.code,e.read()[:60])
PY
