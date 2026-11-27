#!/usr/bin/env bash
set -u
python3 - <<'PY'
import json,urllib.request,urllib.parse,urllib.error
KC="http://127.0.0.1:30087"; REALM="corp"
def req(m,p,b=None,t=None,form=False):
    d=None;h={}
    if b is not None:
        if form: d=urllib.parse.urlencode(b).encode();h["Content-Type"]="application/x-www-form-urlencoded"
        else: d=json.dumps(b).encode();h["Content-Type"]="application/json"
    if t: h["Authorization"]="Bearer "+t
    r=urllib.request.Request(KC+p,data=d,headers=h,method=m)
    try:
        with urllib.request.urlopen(r,timeout=90) as x: return x.status,x.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()
st,t=req("POST","/realms/master/protocol/openid-connect/token",{"grant_type":"password","client_id":"admin-cli","username":"admin","password":"__KEYCLOAK_ADMIN_PASS__"},form=True)
T=json.loads(t)["access_token"]
st,r=req("GET",f"/admin/realms/{REALM}",t=T); realm_id=json.loads(r)["id"]
print("realm id:", realm_id)
st,c=req("GET",f"/admin/realms/{REALM}/components",t=T)
for x in json.loads(c):
    print(f"  {x['id']} {x['name']} type={x['providerType']} parentId={x['parentId']}")
comp=[x for x in json.loads(c) if x["providerId"]=="ldap"][0]
comp["parentId"]=realm_id
cfg={k:list(v) for k,v in comp["config"].items()}; cfg["debug"]=["false"]
comp["config"]=cfg
print("fix parentId:", req("PUT", f"/admin/realms/{REALM}/components/{comp['id']}", comp, t=T)[0])
print("sync:", *req("POST", f"/admin/realms/{REALM}/user-storage/{comp['id']}/sync?action=triggerFullSync", {}, t=T))
PY
