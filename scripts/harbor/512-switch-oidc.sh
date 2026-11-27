#!/usr/bin/env bash
set -u
python3 - <<'PY'
import json,base64,urllib.request,urllib.error
H="http://127.0.0.1:30090"; AUTH="Basic "+base64.b64encode(b"admin:__HARBOR_ADMIN_PASS__").decode()
def req(m,p,b=None):
    d=json.dumps(b).encode() if b is not None else None
    h={"Authorization":AUTH}
    if d: h["Content-Type"]="application/json"
    r=urllib.request.Request(H+p,data=d,headers=h,method=m)
    try:
        with urllib.request.urlopen(r,timeout=60) as x: return x.status,x.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()
st,r=req("GET","/api/v2.0/configurations")
cfg=json.loads(r)
for k in ("auth_mode","ldap_url","oidc_endpoint","oidc_client_id","oidc_groups_claim","oidc_admin_group"):
    print(f"{k} = {cfg.get(k)}")
new={"auth_mode":"oidc","oidc_name":"Keycloak","oidc_endpoint":"http://192.168.200.12:30087/realms/corp",
     "oidc_client_id":"harbor","oidc_client_secret":"__HARBOR_OIDC_SECRET__",
     "oidc_groups_claim":"groups","oidc_user_claim":"preferred_username",
     "oidc_scope":"openid,profile,email,groups","oidc_verify_cert":False,
     "oidc_auto_onboard":True,"oidc_admin_group":"platform-admins","oidc_group_filter":""}
print("PUT:",*req("PUT","/api/v2.0/configurations",new))
st,r=req("GET","/api/v2.0/configurations")
c2=json.loads(r)
for k in ("auth_mode","oidc_endpoint","oidc_client_id","oidc_groups_claim","oidc_admin_group","oidc_scope"):
    print(f"now {k} = {c2.get(k)}")
PY
