#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H,base64,json
for user in ["dev01","lead01"]:
    cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    r=op.open("http://192.168.200.12:30080/auth/login",timeout=60)
    act=H.unescape(re.search(r'id="kc-form-login"[^>]*action="([^"]+)"',r.read().decode(errors="ignore")).group(1))
    op.open(urllib.request.Request(act,data=urllib.parse.urlencode({"username":user,"password":"__LDAP_USER_INIT_PASS__"}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST"),timeout=90)
    tok=[c.value for c in cj if c.name=="argocd.token"]
    if not tok: print(user,"no cookie"); continue
    p=tok[0].split(".")[1]
    cl=json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4)))
    print(user,"sub:",cl.get("sub"),"email:",cl.get("email"),"groups:",cl.get("groups"))
PY
