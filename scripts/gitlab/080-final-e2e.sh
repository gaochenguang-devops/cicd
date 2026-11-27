#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H,json
GL="http://192.168.200.12"
cj=http.cookiejar.CookieJar();op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
page=op.open(GL+"/users/sign_in",timeout=30).read().decode(errors="ignore")
tok=re.search(r'name="authenticity_token" value="([^"]+)"',page).group(1)
req=urllib.request.Request(GL+"/users/auth/openid_connect",data=urllib.parse.urlencode({"authenticity_token":tok}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST")
kc=op.open(req,timeout=60).read().decode(errors="ignore")
action=H.unescape(re.search(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"',kc).group(1))
req2=urllib.request.Request(action,data=urllib.parse.urlencode({"username":"dev01","password":"__LDAP_USER_INIT_PASS__"}).encode(),headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST")
r=op.open(req2,timeout=90); body=r.read().decode(errors="ignore")
print("final url:",r.geturl()[:140])
i=body.find("gl-alert-body")
if i>0: print("ALERT:",re.sub(r"<[^>]+>","",body[i:i+400]).strip()[:300])
try:
    u=json.load(op.open(GL+"/api/v4/user",timeout=30))
    print("gitlab user:",u.get("username"),u.get("email"),u.get("state"))
except Exception as e: print("api err:",e)
PY
