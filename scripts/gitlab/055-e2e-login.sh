#!/usr/bin/env bash
set -u
python3 - <<'PY'
import re,urllib.request,urllib.parse,http.cookiejar,html as H
GL="http://127.0.0.1:80"
cj=http.cookiejar.CookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
# 1) start omniauth
page=op.open(GL+"/users/sign_in",timeout=30).read().decode(errors="ignore")
tok=re.search(r'name="authenticity_token" value="([^"]+)"',page).group(1)
req=urllib.request.Request(GL+"/users/auth/openid_connect",data=urllib.parse.urlencode({"authenticity_token":tok}).encode(),
    headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST")
kc=op.open(req,timeout=60).read().decode(errors="ignore")
form=re.search(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"',kc)
action=H.unescape(form.group(1))
print("kc action:",action[:80])
# 2) submit credentials
data=urllib.parse.urlencode({"username":"dev01","password":"__LDAP_USER_INIT_PASS__","credentialId":""}).encode()
req2=urllib.request.Request(action,data=data,headers={"Content-Type":"application/x-www-form-urlencoded"},method="POST")
r=op.open(req2,timeout=90)
body=r.read().decode(errors="ignore")
print("after kc login url:",r.geturl()[:120])
# 3) who am I in GitLab
try:
    r3=op.open(GL+"/api/v4/user",timeout=30)
    print("gitlab user:",r3.read().decode()[:300])
except Exception as e:
    print("api err:",e)
PY
