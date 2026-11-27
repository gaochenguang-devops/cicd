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
        with urllib.request.urlopen(r,timeout=60) as x: return x.status,x.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()
def j(s): 
    try: return json.loads(s)
    except: return None
st,t=req("POST","/realms/master/protocol/openid-connect/token",{"grant_type":"password","client_id":"admin-cli","username":"admin","password":"__KEYCLOAK_ADMIN_PASS__"},form=True)
T=j(t)["access_token"]

# groups scope
st,scopes=req("GET",f"/admin/realms/{REALM}/client-scopes",t=T); scopes=j(scopes)
gs=[s["id"] for s in scopes if s["name"]=="groups"]
if not gs:
    st,_=req("POST",f"/admin/realms/{REALM}/client-scopes",
      {"name":"groups","protocol":"openid-connect","attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"}},t=T)
    print("scope create:",st)
    st,scopes=req("GET",f"/admin/realms/{REALM}/client-scopes",t=T); scopes=j(scopes)
    gs=[s["id"] for s in scopes if s["name"]=="groups"]
gid=gs[0]
st,mm=req("GET",f"/admin/realms/{REALM}/client-scopes/{gid}/protocol-mappers/models",t=T); mm=j(mm) or []
if not any(m["protocolMapper"]=="oidc-group-membership-mapper" for m in mm):
    st,_=req("POST",f"/admin/realms/{REALM}/client-scopes/{gid}/protocol-mappers/models",
      {"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-group-membership-mapper",
       "config":{"claim.name":"groups","full.path":"false","id.token.claim":"true",
                 "access.token.claim":"true","userinfo.token.claim":"true"}},t=T)
    print("groups mapper create:",st)
req("PUT",f"/admin/realms/{REALM}/default-default-client-scopes/{gid}",{},t=T)
print("groups scope set default")

CLIENTS=[
 ("gitlab","GitLab","http://192.168.200.12/users/auth/openid_connect/callback","__GITLAB_OIDC_SECRET__"),
 ("jenkins","Jenkins","http://192.168.200.12:30088/securityRealm/finishLogin","__JENKINS_OIDC_SECRET__"),
 ("argocd","ArgoCD","http://192.168.200.12:30080/auth/callback","ArgoCDOIDC@2026Secret"),
 ("harbor","Harbor","http://192.168.200.12:30090/c/oidc/callback","__HARBOR_OIDC_SECRET__"),
]
for cid,name,uri,secret in CLIENTS:
    body={"clientId":cid,"name":name,"enabled":True,"protocol":"openid-connect","publicClient":False,
          "secret":secret,"standardFlowEnabled":True,"directAccessGrantsEnabled":True,
          "serviceAccountsEnabled":False,"redirectUris":[uri],"webOrigins":["+"],
          "attributes":{"post.logout.redirect.uris":"+","pkce.code.challenge.method":"S256"}}
    st,r=req("POST",f"/admin/realms/{REALM}/clients",body,t=T)
    if st==201: print(f"client {cid}: created")
    else:
        st2,cs=req("GET",f"/admin/realms/{REALM}/clients?clientId={cid}",t=T); cs=j(cs) or []
        if cs:
            st,_=req("PUT",f"/admin/realms/{REALM}/clients/{cs[0]['id']}",body,t=T); print(f"client {cid}: update {st}")
        else: print(f"client {cid}: FAIL {st} {r[:150]}")
st,cs=req("GET",f"/admin/realms/{REALM}/clients",t=T); cs=j(cs) or []
print("clients now:",[c["clientId"] for c in cs])
PY
