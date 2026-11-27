#!/usr/bin/env bash
set -u
python3 - <<'PY'
import json,urllib.request,urllib.parse,urllib.error,time
KC="http://127.0.0.1:30087"; REALM="corp"; LDAP_ID="ZyMe9em9Q1ep6T5xmOx65A"
def req(m,p,b=None,t=None,form=False):
    d=None;h={}
    if b is not None:
        if form: d=urllib.parse.urlencode(b).encode();h["Content-Type"]="application/x-www-form-urlencoded"
        else: d=json.dumps(b).encode();h["Content-Type"]="application/json"
    if t: h["Authorization"]="Bearer "+t
    r=urllib.request.Request(KC+p,data=d,headers=h,method=m)
    try:
        with urllib.request.urlopen(r,timeout=120) as x: return x.status,x.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()
st,t=req("POST","/realms/master/protocol/openid-connect/token",{"grant_type":"password","client_id":"admin-cli","username":"admin","password":"__KEYCLOAK_ADMIN_PASS__"},form=True)
T=json.loads(t)["access_token"]
st,c=req("GET",f"/admin/realms/{REALM}/components",t=T); comps=json.loads(c)
gm=[x for x in comps if x["providerId"]=="group-ldap-mapper"]
if not gm:
    body={"name":"groups","providerId":"group-ldap-mapper",
          "providerType":"org.keycloak.storage.ldap.mappers.LDAPStorageMapper","parentId":LDAP_ID,
          "config":{"groups.dn":["ou=groups,dc=corp,dc=local"],
            "group.name.ldap.attribute":["cn"],
            "group.object.classes":["groupOfNames"],
            "preserve.group.inheritance":["false"],
            "membership.ldap.attribute":["member"],
            "membership.attribute.type":["DN"],
            "membership.user.ldap.attribute":["uid"],
            "groups.filter":[""],
            "mode":["READ_ONLY"],
            "user.roles.retrieve.strategy":["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
            "memberof.ldap.attribute":["memberOf"],
            "ignore.missing.groups":["true"],
            "groups.subgroup.attribute":[],
            "groups.path.separator":[]}}
    st,r=req("POST",f"/admin/realms/{REALM}/components",body,t=T)
    print("group mapper create:",st,r[:200])
else:
    print("exists:",gm[0]["id"])
print("sync full:", *req("POST", f"/admin/realms/{REALM}/user-storage/{LDAP_ID}/sync?action=triggerFullSync", {}, t=T))
time.sleep(2)
st,u=req("GET",f"/admin/realms/{REALM}/users?max=100&briefRepresentation=true",t=T); us=json.loads(u)
print("users:",len(us),[x["username"] for x in us])
st,g=req("GET",f"/admin/realms/{REALM}/groups?max=100",t=T); gs=json.loads(g)
print("groups:",[(x["name"],len(x.get("subGroups",[]))) for x in gs])
for x in gs:
    st,m=req("GET",f"/admin/realms/{REALM}/groups/{x['id']}/members?max=100&briefRepresentation=true",t=T)
    print("  ",x["name"],"->",[y["username"] for y in json.loads(m)])
PY
