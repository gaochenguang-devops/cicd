#!/usr/bin/env bash
# 配置 Keycloak：realm corp + LDAP 联邦（用户/组）+ groups client scope + 4 个 OIDC client
set -uo pipefail
KC=http://127.0.0.1:30087

python3 - <<'PY'
import json, urllib.request, urllib.parse, urllib.error, sys

KC="http://127.0.0.1:30087"
ADMIN=("admin","__KEYCLOAK_ADMIN_PASS__")
REALM="corp"

def req(method, path, body=None, token=None, form=False):
    url=KC+path
    data=None; headers={}
    if body is not None:
        if form:
            data=urllib.parse.urlencode(body).encode(); headers["Content-Type"]="application/x-www-form-urlencoded"
        else:
            data=json.dumps(body).encode(); headers["Content-Type"]="application/json"
    if token: headers["Authorization"]="Bearer "+token
    r=urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw=resp.read()
            return resp.status, (json.loads(raw) if raw.strip().startswith(b"{") or raw.strip().startswith(b"[") else raw.decode())
    except urllib.error.HTTPError as e:
        raw=e.read()
        return e.code, raw.decode()[:400]

# 1) admin token
st, tok = req("POST","/realms/master/protocol/openid-connect/token",
              {"grant_type":"password","client_id":"admin-cli","username":ADMIN[0],"password":ADMIN[1]}, form=True)
assert st==200 and isinstance(tok,dict), f"admin token failed: {st} {tok}"
T=tok["access_token"]
print("  admin token OK")

# 2) realm
st, r = req("GET", f"/admin/realms/{REALM}", token=T)
if st!=200:
    st, r = req("POST","/admin/realms", {"realm":REALM,"enabled":True,"displayName":"Corp 统一身份",
                                         "loginWithEmailAllowed":True,"duplicateEmailsAllowed":False,
                                         "registrationAllowed":False,"rememberMe":True}, token=T)
    print("  realm 创建:", st)
else:
    print("  realm 已存在")

# 3) LDAP 用户联邦
st, comps = req("GET", f"/admin/realms/{REALM}/components?type=org.keycloak.storage.UserStorageProvider", token=T)
ldap_id=None
if isinstance(comps,list):
    for c in comps:
        if c.get("providerId")=="ldap": ldap_id=c["id"]
if ldap_id:
    print("  LDAP 联邦已存在:", ldap_id)
else:
    body={
      "name":"corp-ldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider",
      "parentId":REALM,"config":{
        "enabled":["true"],"priority":["0"],"cachePolicy":["DEFAULT"],"batchSizeForSync":["1000"],
        "editMode":["READ_ONLY"],"importEnabled":["true"],"syncRegistrations":["false"],
        "vendor":["other"],"usernameLDAPAttribute":["uid"],"rdnLDAPAttribute":["uid"],
        "uuidLDAPAttribute":["entryUUID"],"userObjectClasses":["inetOrgPerson, organizationalPerson, person"],
        "connectionUrl":["ldap://192.168.200.12:389"],"usersDn":["ou=people,dc=corp,dc=local"],
        "authType":["simple"],"bindDn":["cn=admin,dc=corp,dc=local"],"bindCredential":["__LDAP_ADMIN_PASS__"],
        "searchScope":["2"],"validatePasswordPolicy":["false"],"trustEmail":["true"],
        "connectionPooling":["true"],"pagination":["true"],"allowKerberosAuthentication":["false"],
        "useKerberosForPasswordAuthentication":["false"],"debug":["false"]
      }}
    st, _ = req("POST", f"/admin/realms/{REALM}/components", body, token=T)
    print("  LDAP 联邦创建:", st)
    st, comps = req("GET", f"/admin/realms/{REALM}/components?type=org.keycloak.storage.UserStorageProvider", token=T)
    ldap_id=[c["id"] for c in comps if c.get("providerId")=="ldap"][0]

# 4) 组映射器
st, subs = req("GET", f"/admin/realms/{REALM}/components?parent={ldap_id}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper", token=T)
has_group=any(s.get("providerId")=="group-ldap-mapper" for s in (subs if isinstance(subs,list) else []))
if has_group:
    print("  组映射器已存在")
else:
    body={"name":"group-mapper","providerId":"group-ldap-mapper",
          "providerType":"org.keycloak.storage.ldap.mappers.LDAPStorageMapper","parentId":ldap_id,
          "config":{
            "groups.dn":["ou=groups,dc=corp,dc=local"],
            "group.name.ldap.attribute":["cn"],
            "group.object.classes":["groupOfNames"],
            "membership.ldap.attribute":["member"],
            "membership.attribute.type":["DN"],
            "membership.user.ldap.attribute":["uid"],
            "groups.path":["/"],
            "mode":["READ_ONLY"],
            "user.object.classes":["inetOrgPerson, organizationalPerson, person"],
            "preserve.group.inheritance":["false"],
            "ignore.missing.groups":["false"],
            "drop.non.existing.groups.during.sync":["false"],
            "membership.retrieval.strategy":["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]
          }}
    st, r = req("POST", f"/admin/realms/{REALM}/components", body, token=T)
    print("  组映射器创建:", st, r if st>=300 else "")

# 5) 触发全量同步
st, r = req("POST", f"/admin/realms/{REALM}/user-storage/{ldap_id}/sync?action=triggerFullSync", {}, token=T)
print("  触发同步:", st, r if isinstance(r,dict) else r)

# 6) groups client scope + mapper
st, scopes = req("GET", f"/admin/realms/{REALM}/client-scopes", token=T)
gs=None
for s in scopes if isinstance(scopes,list) else []:
    if s["name"]=="groups": gs=s["id"]
if not gs:
    st, _ = req("POST", f"/admin/realms/{REALM}/client-scopes",
                {"name":"groups","protocol":"openid-connect","attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"}}, token=T)
    st, scopes = req("GET", f"/admin/realms/{REALM}/client-scopes", token=T)
    gs=[s["id"] for s in scopes if s["name"]=="groups"][0]
    print("  client scope groups 创建:", st)
st, mappers = req("GET", f"/admin/realms/{REALM}/client-scopes/{gs}/protocol-mappers/models", token=T)
if not any(m.get("protocolMapper")=="oidc-group-membership-mapper" for m in (mappers if isinstance(mappers,list) else [])):
    st, _ = req("POST", f"/admin/realms/{REALM}/client-scopes/{gs}/protocol-mappers/models",
        {"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-group-membership-mapper",
         "config":{"claim.name":"groups","full.path":"false","id.token.claim":"true",
                   "access.token.claim":"true","userinfo.token.claim":"true"}}, token=T)
    print("  groups mapper 创建:", st)
# 设为默认 scope，所有 client 都带上 groups
req("PUT", f"/admin/realms/{REALM}/default-default-client-scopes/{gs}", {}, token=T)

# 7) clients
CLIENTS=[
 ("gitlab","GitLab","http://192.168.200.12/users/auth/openid_connect/callback","__GITLAB_OIDC_SECRET__"),
 ("jenkins","Jenkins","http://192.168.200.12:30088/securityRealm/finishLogin","__JENKINS_OIDC_SECRET__"),
 ("argocd","ArgoCD","http://192.168.200.12:30080/auth/callback","ArgoCDOIDC@2026Secret"),
 ("harbor","Harbor","http://192.168.200.12:30090/c/oidc/callback","__HARBOR_OIDC_SECRET__"),
]
for cid, name, uri, secret in CLIENTS:
    body={"clientId":cid,"name":name,"enabled":True,"protocol":"openid-connect",
          "publicClient":False,"secret":secret,"standardFlowEnabled":True,
          "directAccessGrantsEnabled":True,"serviceAccountsEnabled":False,
          "redirectUris":[uri],"webOrigins":["+"],
          "attributes":{"post.logout.redirect.uris":"+","pkce.code.challenge.method":"S256"}}
    st, r = req("POST", f"/admin/realms/{REALM}/clients", body, token=T)
    if st==409:
        st2, cs = req("GET", f"/admin/realms/{REALM}/clients?clientId={cid}", token=T)
        cid_uuid=cs[0]["id"]
        st, _ = req("PUT", f"/admin/realms/{REALM}/clients/{cid_uuid}", body, token=T)
        print(f"  client {cid}: 更新 {st}")
    else:
        print(f"  client {cid}: 创建 {st}")

# 8) 同步结果
st, users = req("GET", f"/admin/realms/{REALM}/users?max=200", token=T)
st, groups = req("GET", f"/admin/realms/{REALM}/groups?max=200", token=T)
print("  用户数:", len(users) if isinstance(users,list) else users)
print("  组:", [g["name"] for g in groups] if isinstance(groups,list) else groups)
PY
