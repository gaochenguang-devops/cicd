#!/usr/bin/env bash
set -u
python3 - <<'PY'
import urllib.request,urllib.parse,urllib.error,json,base64
BASE="http://127.0.0.1:30088"
H={"Authorization":"Basic "+base64.b64encode(b"lead01:__LDAP_USER_INIT_PASS__").decode()}
r=urllib.request.Request(BASE+"/crumbIssuer/api/json",headers=H)
crumb=json.load(urllib.request.urlopen(r,timeout=30))
field,val=crumb["crumbRequestField"],crumb["crumb"]
print("crumb ok:",field,val[:20])
d=urllib.parse.urlencode({field:val,"json":json.dumps({"items":[]}),"Submit":"Yes"}).encode()
req=urllib.request.Request(BASE+"/configuration-as-code/reload",data=d,
    headers={**H,"Content-Type":"application/x-www-form-urlencoded"},method="POST")
try:
    with urllib.request.urlopen(req,timeout=180) as x:
        print("reload:",x.status,x.geturl())
        print(x.read().decode()[:300])
except urllib.error.HTTPError as e:
    print("reload err:",e.code,e.geturl())
    print(e.read().decode()[:500])
PY
