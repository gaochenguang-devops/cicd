# 统一账号体系对接手册：OpenLDAP → Keycloak → GitLab / Jenkins / ArgoCD / Harbor

> 适用环境：单节点 K8s（Rocky Linux，`192.168.200.12`）。
> 目标：所有服务不再各自直连 LDAP，统一由 Keycloak 提供 OIDC 单点登录，账号与分组仍来自 OpenLDAP（`dc=corp,dc=local`）。
> 本手册按“照着敲就能通”的顺序编写，每一步都有 **验证命令 + 预期结果 + 常见报错怎么修**。
>
> **⚠️ 访问地址已统一到 `https://*.corp.local`（2026-11-27 完成切换）**。正文里出现的 `http://192.168.200.12:300xx` 是**当时的接入方式与排障记录**，仍可用于直连排障；但 OIDC 的 issuer、各处回调地址现在都是 https 域名：
>
> | 系统 | 现用入口 | 回调（Keycloak client redirectUri） |
> | --- | --- | --- |
> | Keycloak | `https://keycloak.corp.local` | — |
> | GitLab | `https://gitlab.corp.local` | `https://gitlab.corp.local/users/auth/openid_connect/callback` |
> | Jenkins | `https://jenkins.corp.local` | `https://jenkins.corp.local/securityRealm/finishLogin` |
> | Harbor | `https://harbor.corp.local` | `https://harbor.corp.local/c/oidc/callback` |
> | Sonar | `https://sonar.corp.local` | `https://sonar.corp.local/oauth2/callback/oidc` |
> | ArgoCD | `https://argocd.corp.local` | `https://argocd.corp.local/api/dex/callback`（client **`argocd-dex`**，不是 `argocd`） |
>
> **两个容易踩的点（2026-11-27 已修）**：
> 1. **ArgoCD 的 Keycloak client 是 `argocd-dex`**。`argocd` 这个 client 存在但登录链路根本不用它，改 `argocd` 的回调不会生效，必须改 `argocd-dex`（`https://argocd.corp.local/api/dex/callback`）。
> 2. **Harbor 的回调地址由 `EXT_ENDPOINT` 生成**，不是由浏览器入口决定。`EXT_ENDPOINT=http://192.168.200.12:30090` 时，即便从 `https://harbor.corp.local` 点登录，发出的 `redirect_uri` 也是 http + IP，Keycloak 必然报 `Invalid parameter: redirect_uri`。现已把 `EXT_ENDPOINT` 改为 `https://harbor.corp.local`，并配套改了 containerd / CI / Jib 的镜像地址（详见 §11）。
>
> 切换细节、CA 信任注入与踩坑见 `docs/01-入口与网络/访问层与证书.md` 6.1 / 5.9。


---

## 0. 最终架构

```
OpenLDAP (dc=corp,dc=local, 389)
        │  用户同步 / 密码校验（Keycloak User Storage Provider，READ_ONLY）
        ▼
Keycloak 26.6.4  https://keycloak.corp.local            realm: corp
        │  OIDC (Authorization Code)
        ├── GitLab   https://gitlab.corp.local         (provider: openid_connect)
        ├── Jenkins  https://jenkins.corp.local        (插件: oic-auth)
        ├── Harbor   https://harbor.corp.local         (auth_mode: oidc_auth)
        ├── Sonar    https://sonar.corp.local          (插件: sonar-auth-oidc)
        └── ArgoCD   https://argocd.corp.local         (dex.config → oidc connector → Keycloak)
```

> ArgoCD 为什么走 Dex：ArgoCD 内置的 OIDC 验签器实测无法通过 Keycloak 26.6 签发的 id_token（`failed to verify id token signature`，但同一 token 用公钥可验签成功、Harbor/Jenkins 也能验）。官方支持的做法是使用 Dex 作为 OIDC 中转，详见 [第 7.4 节](#74-argocd走-dex-桥接)。其余三个服务全部直连 Keycloak。

---

## 1. 开工前信息表

把这些值抄到一张纸上，后面每一步都会用到。

| 项目 | 值 |
|---|---|
| 服务器 | `192.168.200.12`，root / ${SSH_ROOT_PASS} |
| Keycloak | `https://keycloak.corp.local`（应急 NodePort `:30087`），admin / `${KEYCLOAK_ADMIN_PASS}` |
| realm | `corp`，realm UUID = `b145c645-01c7-414c-9860-ec765bc46ba2` |
| LDAP | `ldap://192.168.200.12:389`，`dc=corp,dc=local`，admin `cn=admin,dc=corp,dc=local` |
| 用户 | `ou=people`，登录名属性 `uid`，初始密码 `${LDAP_USER_INIT_PASS}` |
| 组 | `ou=groups`，`groupOfNames`，`member` |
| 组成员 | platform-admins=[lead01] / devops=[ops01,ops02] / developers=[dev01..dev05] / qa=[qa01,qa02] |
| GitLab | `https://gitlab.corp.local`（直连 `http://192.168.200.12`），root / `${GITLAB_ROOT_PASS}` |
| Jenkins | `https://jenkins.corp.local`（应急 NodePort `:30088`，agent `:30089`） |
| Harbor | `https://harbor.corp.local`（直连 `:30090` 仅排障），admin / `${HARBOR_ADMIN_PASS}` |
| ArgoCD | `https://argocd.corp.local`（应急 NodePort `:30080`），admin / `${ARGOCD_ADMIN_PASS}` |

OIDC 客户端（在 Keycloak 里创建，密钥自定义后同步到各服务）：

| clientId | clientSecret | redirect URI |
|---|---|---|
| `gitlab` | `${GITLAB_OIDC_SECRET}` | `https://gitlab.corp.local/users/auth/openid_connect/callback` |
| `jenkins` | `${JENKINS_OIDC_SECRET}` | `https://jenkins.corp.local/securityRealm/finishLogin` |
| `harbor` | `${HARBOR_OIDC_SECRET}` | `https://harbor.corp.local/c/oidc/callback`（由 `EXT_ENDPOINT` 生成） |
| `argocd-dex` | `${ARGOCD_DEX_OIDC_SECRET}` | `https://argocd.corp.local/api/dex/callback`（+ 旧 http 一条保回滚） |
| `sonarqube` | `${SONAR_OIDC_SECRET}` | `https://sonar.corp.local/oauth2/callback/oidc` |
| `artifactory` | `${ARTIFACTORY_OIDC_SECRET}` | `https://artifactory.corp.local/ui/api/v1/oauth2/callback` |
| `cli-test`（只用于手工验 token，无浏览器流程） | `${CLI_TEST_OIDC_SECRET}` | 无 |

> 七个业务客户端（`gitlab` / `jenkins` / `harbor` / `argocd-dex` / `sonarqube` / `artifactory`，外加 `argocd` 供 ArgoCD 自身 OIDC）都应为 `standardFlowEnabled=true`、`implicitFlowEnabled=false`、`directAccessGrantsEnabled=false`。`cli-test` 是专门留的“密码模式”验证客户端（第 5.3 节用），业务客户端不要开口令模式。

> 如果还想让 ArgoCD 直连 OIDC，可另外建 `argocd` 客户端（redirect `http://192.168.200.12:30080/auth/callback`），但按本手册最终使用的是 `argocd-dex`。

**两个通用小工具**（后面反复用到，建议先在你的机器上定义好）：

```bash
# 取 Keycloak admin token
kc_token() {
  curl -s -d "client_id=admin-cli&username=admin&password=${KEYCLOAK_ADMIN_PASS}&grant_type=password" \
    http://192.168.200.12:30087/realms/master/protocol/openid-connect/token \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])'
}
# 取 realm UUID（后面 parentId 必须用它）
curl -s -H "Authorization: Bearer $(kc_token)" \
  http://192.168.200.12:30087/admin/realms/corp | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])'
```

---

## 2. 部署 Keycloak + Postgres

目录：`manifests/keycloak/`（`00-base.yaml` 含 namespace / Secret / PV，`10-deployment.yaml` 含 Postgres 与 Keycloak）。

```bash
kubectl apply -f manifests/keycloak/00-base.yaml
kubectl apply -f manifests/keycloak/10-deployment.yaml
kubectl -n keycloak rollout status deploy/keycloak-db --timeout=180s
kubectl -n keycloak rollout status deploy/keycloak --timeout=300s
```

**验证**（浏览器或 curl 均可）：

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.200.12:30087/realms/master/.well-known/openid-configuration
# 预期：200
```

要点 / 坑：

1. **镜像必须是 26.6.x**。`26.4` 存在已知问题：LDAP 同步直接返回 `400 UnknownError` 且导入 0 个用户。升级方式：
   ```bash
   kubectl -n keycloak set image deploy/keycloak keycloak=quay.io/keycloak/keycloak:26.6.4
   kubectl -n keycloak rollout status deploy/keycloak --timeout=300s
   ```
   Keycloak 首启会自动把数据库迁移到 26.6 的 schema，无需手工处理。
2. 数据必须落盘：PVC `keycloak-pg` → `/data/keycloak/pg`（5Gi，Retain），否则重启后 realm/用户全丢。
3. `KC_HOSTNAME_STRICT=false` 允许用 IP:NodePort 访问；**不要**设置 `KC_HOSTNAME` 为 `localhost`，否则 token 里的 `iss` 会变成内网不可达地址。
4. 排障期间可以临时加 `KC_LOG_LEVEL=DEBUG`，**对接完成后必须删掉**（见第 9 节清理项）。

---

## 3. 创建 realm `corp`

控制台方式：登录 `:30087` → 左上角下拉 → **Create realm** → Realm name 填 `corp` → Create。
命令行方式（幂等）：

```bash
T=$(kc_token)
curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"realm":"corp","enabled":true,"displayName":"Corp 统一身份"}' \
  http://192.168.200.12:30087/admin/realms
```

**验证**：

```bash
curl -s -H "Authorization: Bearer $(kc_token)" http://192.168.200.12:30087/admin/realms/corp \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["realm"], d["id"])'
# 预期：corp b145c645-01c7-414c-9860-ec765bc46ba2（UUID 因环境而异，记下来！）
```

---

## 4. LDAP 联邦（User Storage Provider）

### 4.1 建组件

控制台：`corp` realm → **User federation** → **Add Ldap provider**，按下表填：

| 字段 | 值 |
|---|---|
| Vendor | Other |
| Connection URL | `ldap://192.168.200.12:389` |
| Bind type | simple |
| Bind DN | `cn=admin,dc=corp,dc=local` |
| Bind credential | LDAP admin 密码 |
| Edit mode | READ_ONLY |
| Users DN | `ou=people,dc=corp,dc=local` |
| Username LDAP attribute | `uid` |
| RDN LDAP attribute | `uid` |
| UUID LDAP attribute | `entryUUID` |
| User object classes | `inetOrgPerson, organizationalPerson, person` |
| Import Users | On |
| Sync Registrations | Off |
| Trust Email | On |
| Pagination / Connection pooling | On |
| Search scope | Subtree(2) |
| Batch size | 1000 |

### 4.2 ⚠️ 最容易翻车的一步：`parentId` 必须是 realm UUID

通过 Admin REST 建组件时，如果 `parentId` 写成了 realm 名字（`corp`）而不是 **realm 的 UUID**，Keycloak 会在同步时抛：

```
ModelIllegalStateException: Realm with id corp not found
    at UserStorageSyncTask.getStorageModel
```

表现为：`testLDAPConnection` 返回 204（网络和绑定都没问题），但同步 400 且导入 0 个用户；`KC_LOG_LEVEL=DEBUG` 才能看到上面这行。

**建组件时正确的请求体**（`parentId` 用第 3 步查到的 UUID）：

```bash
T=$(kc_token); RID=b145c645-01c7-414c-9860-ec765bc46ba2   # ← 换成你自己的 realm UUID
curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
 -d '{
  "name":"corp-ldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider",
  "parentId":"'"$RID"'",
  "config":{
    "enabled":["true"],"vendor":["other"],"connectionUrl":["ldap://192.168.200.12:389"],
    "authType":["simple"],"bindDn":["cn=admin,dc=corp,dc=local"],"bindCredential":["<LDAP admin 密码>"],
    "usersDn":["ou=people,dc=corp,dc=local"],"usernameLDAPAttribute":["uid"],"rdnLDAPAttribute":["uid"],
    "uuidLDAPAttribute":["entryUUID"],"userObjectClasses":["inetOrgPerson, organizationalPerson, person"],
    "editMode":["READ_ONLY"],"importEnabled":["true"],"syncRegistrations":["false"],
    "trustEmail":["true"],"pagination":["true"],"connectionPooling":["true"],"searchScope":["2"],
    "batchSizeForSync":["1000"],"cachePolicy":["DEFAULT"],"priority":["0"]
  }}' \
 http://192.168.200.12:30087/admin/realms/corp/components
```

**已经建错的修法**（不用删重建，改 parentId 即可）：

```bash
T=$(kc_token); RID=<realm UUID>; CID=ZyMe9em9Q1ep6T5xmOx65A   # 换成组件 id
# 1) 拉全量组件，本地按 name 过滤（注意：GET /components?type= 过滤参数不生效，必须本地过滤）
curl -s -H "Authorization: Bearer $T" "http://192.168.200.12:30087/admin/realms/corp/components" > /tmp/comps.json
python3 - "$RID" "$CID" "$T" <<'PY'
import sys,json,urllib.request
rid,cid,t=sys.argv[1:4]
comps=json.load(open("/tmp/comps.json"))
c=[x for x in comps if x["id"]==cid][0]
c["parentId"]=rid
req=urllib.request.Request(f"http://192.168.200.12:30087/admin/realms/corp/components/{cid}",
    data=json.dumps(c).encode(),headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="PUT")
print("PUT", urllib.request.urlopen(req).status)   # 预期 204
PY
# 2) 触发全量同步
curl -s -X POST -H "Authorization: Bearer $T" \
  "http://192.168.200.12:30087/admin/realms/corp/user-storage/$CID/sync?action=triggerFullSync"
# 预期返回 {"added":12,"updated":0,"removed":0,...}
```

> 另一条铁律：**组件 `config` 必须是「多值数组」形式**（每个值写成 `["true"]`）。用纯字符串 PUT 会报 `400 Cannot parse the JSON`。

### 4.3 验证用户已导入

```bash
curl -s -H "Authorization: Bearer $(kc_token)" "http://192.168.200.12:30087/admin/realms/corp/users?max=100" \
 | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d),[u["username"] for u in d])'
# 预期：12 个左右，含 dev01..dev05 / ops01 / ops02 / qa01 / qa02 / lead01 / legacy1 / legacy2
```

---

## 5. 组映射器与 `groups` client scope

### 5.1 组映射器

在 LDAP 组件下新建一个 `group-ldap-mapper`（控制台：User federation → corp-ldap → Mappers → Add → group-ldap-mapper）：

| 字段 | 值 |
|---|---|
| Name | `group-ldap-mapper` |
| Groups DN | `ou=groups,dc=corp,dc=local` |
| Group name LDAP attribute | `cn` |
| Group object classes | `groupOfNames` |
| Preserve group inheritance | Off |
| Membership LDAP attribute | `member` |
| Membership attribute type | DN |
| Membership user LDAP attribute | `uid` |
| Mode | READ_ONLY |
| User roles retrieve strategy | LOAD_GROUPS_BY_MEMBER_ATTRIBUTE |
| Ignore missing groups | On |

建完后同样触发一次全量同步（同 4.2 第 2 步），然后验证：

```bash
T=$(kc_token)
for g in developers devops platform-admins qa; do
  echo -n "$g: "
  curl -s -H "Authorization: Bearer $T" "http://192.168.200.12:30087/admin/realms/corp/groups?search=$g" \
   | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "MISSING")'
done
```

控制台核对：`Groups` 页面应看到 4 个组，成员与第 1 节一致。

### 5.2 建 `groups` client scope（让 token 带 groups 声明）

```bash
T=$(kc_token)
curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d '{
 "name":"groups","protocol":"openid-connect","attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"},
 "protocolMappers":[{
   "name":"groups","protocol":"openid-connect",
   "protocolMapper":"oidc-group-membership-mapper",
   "consentRequired":false,
   "config":{"claim.name":"groups","full.path":"false","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}
 }]}' http://192.168.200.12:30087/admin/realms/corp/client-scopes
```

再把它加进 realm 的默认 scope（这样新客户端自动带上）：

```bash
T=$(kc_token); SID=$(curl -s -H "Authorization: Bearer $T" http://192.168.200.12:30087/admin/realms/corp/client-scopes | python3 -c 'import sys,json;print([x["id"] for x in json.load(sys.stdin) if x["name"]=="groups"][0])')
curl -s -X PUT -H "Authorization: Bearer $T" "http://192.168.200.12:30087/admin/realms/corp/default-default-client-scopes/$SID" -o /dev/null -w '%{http_code}\n'
# 预期 204
```

### 5.3 快速验证账号密码 + groups 声明

用专用测试客户端 `cli-test`（开了密码模式，业务客户端都关着）：

```bash
curl -s -d "client_id=cli-test&client_secret=${CLI_TEST_OIDC_SECRET}&grant_type=password&username=dev01&password=${LDAP_USER_INIT_PASS_URLENC}&scope=openid" \
  http://192.168.200.12:30087/realms/corp/protocol/openid-connect/token > /tmp/tok.json
python3 - <<'PY'
import json,base64
d=json.load(open("/tmp/tok.json"))
t=d["id_token"]; p=t.split(".")[1]
c=json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4)))
print("preferred_username:",c["preferred_username"],"groups:",c.get("groups"))
PY
# 预期：dev01 groups: ['developers']
```

---

## 6. 建 4 个 OIDC client

逐个创建（`publicClient:false`、标准授权码流程、禁用隐式/密码模式）。

```bash
T=$(kc_token)
mk_client () {
  local id="$1" secret="$2" redirect="$3" pkce="$4" name="$5"
  curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d '{
   "clientId":"'"$id"'","name":"'"$name"'","enabled":true,"protocol":"openid-connect",
   "publicClient":false,"clientAuthenticatorType":"client-secret","secret":"'"$secret"'",
   "standardFlowEnabled":true,"implicitFlowEnabled":false,"directAccessGrantsEnabled":false,
   "serviceAccountsEnabled":false,"redirectUris":["'"$redirect"'"],
   "attributes":{"pkce.code.challenge.method":"'"$pkce"'","post.logout.redirect.uris":"http://192.168.200.12/*"}
  }' -o /dev/null -w "$id -> %{http_code}\n" http://192.168.200.12:30087/admin/realms/corp/clients
}

mk_client gitlab   ${GITLAB_OIDC_SECRET}   "https://gitlab.corp.local/users/auth/openid_connect/callback" ""      "GitLab"
mk_client jenkins  ${JENKINS_OIDC_SECRET}  "https://jenkins.corp.local/securityRealm/finishLogin"          ""      "Jenkins"
mk_client harbor   ${HARBOR_OIDC_SECRET}   "https://harbor.corp.local/c/oidc/callback"                      "S256"  "Harbor"
mk_client argocd-dex ${ARGOCD_DEX_OIDC_SECRET}  "https://argocd.corp.local/api/dex/callback"                     ""      "ArgoCD-Dex"
# 预期每个都返回 201
```

### PKCE 规则（踩过的大坑）

| 客户端 | PKCE | 原因 |
|---|---|---|
| gitlab / jenkins / argocd-dex | **关闭**（空字符串） | 它们的 OIDC 库默认不发送 `code_challenge`，客户端若开启 S256 会报 `Missing parameter: code_challenge_method` |
| harbor | 保留 `S256` | Harbor 自己会发 PKCE，保留更安全 |

关闭方法（**注意 Keycloak 删 key 不生效，必须显式设空串**）：

```bash
T=$(kc_token)
CID=$(curl -s -H "Authorization: Bearer $T" "http://192.168.200.12:30087/admin/realms/corp/clients?clientId=gitlab" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
python3 - "$CID" "$T" <<'PY'
import sys,json,urllib.request
cid,t=sys.argv[1],sys.argv[2]
u=f"http://192.168.200.12:30087/admin/realms/corp/clients/{cid}"
c=json.load(urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+t})))
a=c.get("attributes") or {}; a["pkce.code.challenge.method"]=""; c["attributes"]=a
urllib.request.urlopen(urllib.request.Request(u,data=json.dumps(c).encode(),
  headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"},method="PUT"))
print("pkce cleared")
PY
```

> 另外：从 attributes 里 pop 掉这个字段 Keycloak 不会真正删除，回读仍然是 S256，所以只能设空串。

---

## 7. 逐服务对接

> 通用原则：**先备份 → 再改配置 → 重启 → 验证 → 失败就回滚**。每个小节的“备份”就是回滚锚点。

### 7.1 GitLab

**备份**

```bash
cp -a /etc/gitlab/gitlab.rb /root/gitlab.rb.bak-$(date +%Y%m%d-%H%M%S)
```

**改 `/etc/gitlab/gitlab.rb`**，追加（注意所有 endpoint 必须是**绝对 URL**，且用 `http`）：

```ruby
gitlab_rails['ldap_enabled'] = false
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_auto_link_user'] = true

gitlab_rails['omniauth_providers'] = [
  {
    name: "openid_connect",
    label: "Keycloak 统一登录",
    args: {
      name: "openid_connect",
      scope: ["openid", "profile", "email", "groups"],
      response_type: "code",
      issuer: "http://192.168.200.12:30087/realms/corp",
      discovery: false,
      client_auth_method: "query",
      uid_field: "preferred_username",
      client_options: {
        identifier: "gitlab",
        secret: "${GITLAB_OIDC_SECRET}",
        redirect_uri: "http://192.168.200.12/users/auth/openid_connect/callback",
        scheme: "http",
        host: "192.168.200.12",
        port: 30087,
        authorization_endpoint: "http://192.168.200.12:30087/realms/corp/protocol/openid-connect/auth",
        token_endpoint:         "http://192.168.200.12:30087/realms/corp/protocol/openid-connect/token",
        userinfo_endpoint:      "http://192.168.200.12:30087/realms/corp/protocol/openid-connect/userinfo",
        jwks_uri:               "http://192.168.200.12:30087/realms/corp/protocol/openid-connect/certs",
        end_session_endpoint:   "http://192.168.200.12:30087/realms/corp/protocol/openid-connect/logout"
      }
    }
  }
]
```

```bash
gitlab-ctl reconfigure
# 约 70 秒；随后 puma 重启，登录页可能短暂 502，等 60~90 秒
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/users/sign_in)" = "200" ]; do sleep 5; done; echo READY
```

**验证**：打开 `http://192.168.200.12/users/sign_in`，应看到「Keycloak 统一登录」按钮；用 `dev01 / ${LDAP_USER_INIT_PASS}` 登录后直接进入 GitLab，右上角是 dev01。

命令行验证（脚本已备）：

```bash
bash scripts/gitlab/080-final-e2e.sh
# 预期输出：
#   final url: http://192.168.200.12/
#   gitlab user: dev01 dev01@corp.local active
```

**四个必踩的坑**

| 症状 | 原因 | 修法 |
|---|---|---|
| `SSL_connect ... wrong version number` | 开了 `discovery: true`，gem 用 HTTPS 打 30087 明文端口 | `discovery: false` + `client_options` 显式给 `scheme:"http"`、`host`、`port` |
| Keycloak 报 `Missing parameter: code_challenge_method` | 客户端开了 S256，GitLab 不发 challenge | 客户端 `pkce.code.challenge.method` 设空串（第 6 节） |
| `undefined method 'include?' for nil`（`net/http addr_port`） | endpoint 写成了相对路径（`/realms/...`），gem 拿不到 host | 所有 endpoint 改为**绝对 URL** |
| 回跳后提示「An account already exists with the email address...」 | 历史 LDAP 用户已存在，未开启邮箱自动关联 | `omniauth_auto_link_user = true`（写 `['email']` 不生效，GitLab 按 provider 名判断） |

> 验证成功后确认数据库里已经生成 identity：
> ```bash
> gitlab-rails runner 'Identity.where(provider:"openid_connect").each{|i| puts "#{i.extern_uid} -> user #{i.user_id}"}'
> # 预期：dev01 -> user 6 之类的输出
> ```
> 模拟登录脚本的坑：cookie 全程必须用 `192.168.200.12`，用 `127.0.0.1` 起手会在回调时报 `Invalid 'state' parameter`（假故障）。

### 7.2 Jenkins（oic-auth 插件 + JCasC）

**备份**

```bash
kubectl -n jenkins get cm jenkins-casc -o yaml > /root/jenkins-sso-bak-$(date +%Y%m%d-%H%M%S).yaml
```

**装插件**：改 `manifests/jenkins/10-deployment.yaml`，在 initContainer 的插件列表里加 `oic-auth`（本次装到 `oic-auth 4.737.vb_3d1a_0e7cf0b_`），然后 `kubectl apply -f manifests/jenkins/10-deployment.yaml`。验证：

```bash
kubectl -n jenkins logs deploy/jenkins -c init --tail=30 | grep -i oic
```

**写 JCasC**（完整文件见 `manifests/jenkins/jenkins-casc-oidc.yaml`），关键部分：

```yaml
jenkins:
  securityRealm:
    oicSecurityRealm:
      clientId: "jenkins"
      clientSecret: "${JENKINS_OIDC_SECRET}"
      serverConfiguration:
        wellKnown:
          wellKnownOpenIDConfigurationUrl: "http://192.168.200.12:30087/realms/corp/.well-known/openid-configuration"
          scopesOverride: "openid profile email groups"
      userNameField: "preferred_username"
      fullNameFieldName: "name"
      emailFieldName: "email"
      groupsFieldName: "groups"
      disableSslVerification: true
      logoutFromOpenidProvider: true
      properties:
        - escapeHatch:
            username: "breakglass"
            secret: "${JENKINS_BREAKGLASS_PASS}"
            group: "platform-admins"
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:platform-admins"
        - "Overall/Read:authenticated"
        - "Job/Build:devops"
        - "Job/Build:developers"
```

**下发并重载**

```bash
kubectl create cm jenkins-casc -n jenkins --from-file=jenkins.yaml=manifests/jenkins/jenkins-casc-oidc.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
sleep 60          # ← ConfigMap 卷挂载有同步延迟，太快 reload 会读到旧配置
bash scripts/jenkins/338-reload-casc.sh   # 内部带 cookie jar + crumb
```

> JCasC 的坑：
> 1. 符号名是 **`oicSecurityRealm`**（不是 `oicAuth`），可先用 `GET /configuration-as-code/schema` 搜 `oic` 确认；
> 2. crumb 必须与同一个 `JSESSIONID` 会话配套，否则 `403 No valid crumb`；
> 3. 第一次 reload 常常“成功”但 realm 没变（ConfigMap 还没同步），隔 1 分钟再 reload 一次；
> 4. realm 生效的标志是：**立刻 401**（LDAP 旧凭据失效），这是正常现象。

**验证**

```bash
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' 'http://192.168.200.12:30088/securityRealm/commenceLogin'
# 预期：303 → Keycloak auth（带 client_id=jenkins，scope=openid profile email groups）
```

浏览器 `:30088` → 点登录 → Keycloak → 回跳后右上角 dev01，权限 `developers`。

**应急账号（必测）**：登录页表单 action 是 `securityRealm/escapeHatch`（不是 `j_spring_security_check`）。已实测 `breakglass / ${JENKINS_BREAKGLASS_PASS}` 可登录，且 `authorities=[authenticated, platform-admins]`（= 管理员）；验证走表单 POST（`securityRealm/escapeHatch`）。

### 7.3 Harbor

Harbor 的认证配置**存在数据库里**，`cm/harbor-core` 的 `app.conf` 改了不生效，必须走 API。

**备份**

```bash
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' http://192.168.200.12:30090/api/v2.0/configurations > /root/harbor-cfg-bak-$(date +%Y%m%d-%H%M%S).json
```

**步骤**

1. 先删掉数据库里已有的 LDAP 用户（否则 Harbor 拒绝切换 auth_mode，报 `auth mode cannot be modified as new users have been inserted into database`）：

```bash
H='-u admin:${HARBOR_ADMIN_PASS}'
for u in dev01 dev02 legacy1 lead01 ops01 ops02 qa01 qa02; do
  curl -s $H -X DELETE "http://192.168.200.12:30090/api/v2.0/users/$u" -o /dev/null -w "$u:%{http_code}\n"
done
```

2. 切换认证：

```bash
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' -X PUT -H 'Content-Type: application/json' \
 -d '{
  "auth_mode":"oidc_auth",
  "oidc_name":"Keycloak",
  "oidc_endpoint":"http://192.168.200.12:30087/realms/corp",
  "oidc_client_id":"harbor",
  "oidc_client_secret":"${HARBOR_OIDC_SECRET}",
  "oidc_scope":"openid,profile,email,groups",
  "oidc_groups_claim":"groups",
  "oidc_user_claim":"preferred_username",
  "oidc_admin_group":"platform-admins",
  "oidc_auto_onboard":true,
  "oidc_verify_cert":false
 }' http://192.168.200.12:30090/api/v2.0/configurations -o /dev/null -w '%{http_code}\n'
# 预期 200
```

> `auth_mode` 的值**必须**是 `oidc_auth`；写 `oidc` 会 400 并提示合法值 `db_auth/ldap_auth/uaa_auth/http_auth/oidc_auth`。

3. 验证：

```bash
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' http://192.168.200.12:30090/api/v2.0/systeminfo | python3 -c 'import sys,json;print(json.load(sys.stdin)["auth_mode"])'
# 预期 oidc_auth
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://192.168.200.12:30090/c/oidc/login
# 预期 302 → Keycloak（带 code_challenge_method=S256）
```

浏览器验证：`:30090` → 「通过 Keycloak 登录」→ dev01 登录 → 能进入项目 `apps`，非管理员。

### 7.4 ArgoCD（走 Dex 桥接）

**为什么不用 ArgoCD 直连 OIDC**

实测直连时：ArgoCD 能拿到 `well-known` 与 JWKS（JWKS 里确实有 token 对应的 `kid`），但日志始终：

```
Failed to verify session token: failed to verify provider token: token verification failed
for all audiences: error for aud "argocd": failed to verify signature: failed to verify id token signature
```

且它自带的“重建 provider 再验一次”的兜底（`newGoOIDCProvider`）也失败；同一个 token 用公钥本地验签**通过**，Harbor/Jenkins 也能验通过，所以是 ArgoCD 这条链路的验签兼容问题。改用官方支持的 Dex 中转后正常。

**备份**

```bash
kubectl -n argocd get cm argocd-cm -o yaml     > /root/argocd-oidc-bak-$(date +%Y%m%d-%H%M%S)-cm.yaml
kubectl -n argocd get cm argocd-rbac-cm -o yaml > /root/argocd-oidc-bak-$(date +%Y%m%d-%H%M%S)-rbac.yaml
```

**配置 `argocd-cm`**（保留 `url`；删掉 `oidc.config`，写 `dex.config`）：

```yaml
data:
  url: http://192.168.200.12:30080
  dex.config: |
    connectors:
    - type: oidc
      id: keycloak
      name: Keycloak
      config:
        issuer: http://192.168.200.12:30087/realms/corp
        clientID: argocd-dex
        clientSecret: ${ARGOCD_DEX_OIDC_SECRET}
        insecureEnableHTTP: true
        insecureSkipEmailVerified: true
        insecureEnableGroups: true      # ← 不加这个，token 里没有 groups，RBAC 全部落到 default
        getUserInfo: true
        scopes:
        - openid
        - profile
        - email
        - groups
    oauth2:
      skipApprovalScreen: true
```

应用并重启：

```bash
kubectl apply -f <(kubectl -n argocd get cm argocd-cm -o json | python3 -c '...')   # 或用脚本 237/238
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=120s
kubectl -n argocd rollout status deploy/argocd-server --timeout=120s
```

现成脚本（幂等）：`scripts/argocd/237-switch-dex-bridge.sh`、`scripts/argocd/238-dex-enable-groups.sh`。

**⚠️ ConfigMap 标签的坑（直连方案也会遇到）**

用 `kubectl apply` 覆盖 `argocd-cm` 时，如果只带 `name/namespace`，会把 `app.kubernetes.io/name=argocd-cm`、`app.kubernetes.io/part-of=argocd` 两个标签清掉。ArgoCD 的 informer 是按标签筛选 ConfigMap 的，标签一丢，pod 立刻 CrashLoop：

```
fatal: configmap "argocd-cm" not found
```

修法：

```bash
kubectl -n argocd label cm argocd-cm app.kubernetes.io/name=argocd-cm app.kubernetes.io/part-of=argocd --overwrite
```

> 因此改 cm 时要么用 `kubectl get cm -o json` 拉全量改完再 apply，要么改完立刻补标签。

**RBAC（`argocd-rbac-cm` 的 `policy.csv`）**

```
g, platform-admins, role:admin
g, devops,          role:admin
g, developers,      role:readonly
g, qa,              role:readonly
```

**验证**

```bash
bash scripts/verify/926-dex-e2e.sh
# 预期：
#   stage: http://192.168.200.12:30087/... (has_kc_form: True)
#   after login: 200 http://192.168.200.12:30080/
#   /api/v1/session/userinfo 200 {"loggedIn":true,"username":"dev01@corp.local","groups":["developers"]}
#   /api/v1/applications 200 {...podinfo...}
```

RBAC 分角色验证（脚本 `scripts/verify/932-rbac-final.sh`，用“删除不存在的项目”判断是否过权限）：

| 用户 | 组 | `DELETE /api/v1/projects/rbac-probe` | 含义 |
|---|---|---|---|
| dev01 / qa01 | developers / qa | `403 permission denied` | readonly 生效 |
| lead01 / ops01 | platform-admins / devops | `404 ...not found` | 已通过 RBAC = admin |

> 直连方案里还有两个独立的坑记录在此，供以后切回直连时参考：
> 1. `auth/login?return_url=` 必须是**绝对 URL**（写 `/applications` 会 400 `Invalid redirect URL`）；
> 2. ArgoCD 的 `oidc.config.requestedScopes` 漏掉 `openid` 会拿不到 id_token（报 `no id_token in token response`），至少写 `["openid","profile","email","groups"]`。

---

### 7.5 SonarQube（OIDC 插件 + Keycloak）

> 完整部署与排障见 `docs/02-流水线与交付/Sonar与Artifactory.md`，这里只写"统一账号"这一段。

1. 插件**只能 v2.1.1**（v3.0.0 与 10.7 插件 API 不兼容，容器起不来）：
   `/data/sonarqube/plugins/sonar-auth-oidc-plugin-2.1.1.jar`，属主 1000。
2. ⚠️ 必须先放开第三方插件风险确认，否则 provider 不注册、登录页没按钮。**`admin` 本地密码已失效**，请用 `sonaradmin`（`${SONAR_ADMIN_PASS}`）或 CI 令牌（`${SONAR_CI_TOKEN}`）：
   ```bash
   curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/settings/set \
     -d 'key=sonar.plugins.risk.consent' -d 'value=ACCEPTED'
   kubectl -n sonar rollout restart deploy/sonarqube
   ```
3. 写 OIDC 参数（`scripts\sonar-jfrog\968-sonar-oidc.sh`）：
   ```
   sonar.auth.oidc.enabled=true
   sonar.auth.oidc.issuerUri=http://192.168.200.12:30087/realms/corp
   sonar.auth.oidc.clientId.secured=sonarqube
   sonar.auth.oidc.clientSecret.secured=${SONAR_OIDC_SECRET}
   sonar.auth.oidc.scopes=openid profile email
   sonar.auth.oidc.loginButtonText=Keycloak
   sonar.auth.oidc.allowUsersToSignUp=true
   sonar.auth.oidc.groupsSync=true
   sonar.auth.oidc.groupsSync.claimName=groups
   sonar.auth.oidc.loginStrategy=Preferred username
   sonar.core.serverBaseURL=http://192.168.200.12:30091
   ```
4. Keycloak client `sonarqube` 的 redirect URI 必须是
   `http://192.168.200.12:30091/oauth2/callback/oidc`（provider key 是 `oidc`，不是 `authoidc`）。
5. 验证：登录页出现「Log in with Keycloak」→ 用 `dev01` 登录成功；
   组同步后 `developers` 组拿到 `scan` 权限、`devops`/`platform-admins` 拿到 `admin`。

### 7.6 JFrog Artifactory（OSS 版只能 LDAP 直连）

OSS 版 OAuth/SAML/HTTP SSO 在 UI 里全灰置，**只能用 LDAP**（与 Keycloak 同一套 OpenLDAP，账号仍统一）：

| 项 | 值 |
|---|---|
| LDAP URL | `ldap://192.168.200.12:389` |
| User DN Pattern | `uid={0},ou=people,dc=corp,dc=local` |
| Manager DN / Password | `cn=admin,dc=corp,dc=local` / `${LDAP_ADMIN_PASS}` |
| Group Member Attribute | **`member`**（不是默认 `uniqueMember`） |
| Group Filter / Base | `(objectClass=groupOfNames)` / `ou=groups,dc=corp,dc=local` |

⚠️ 勾 "Enabled LDAP" 会连带勾上 "Disable Internal Password Login"，导致本地 `admin` 403 —— 去 `Security → General` 取消勾选并保存，保留本地应急入口。

---

## 8. 收尾验证清单（按顺序勾）

- [ ] `Keycloak /realms/corp/.well-known` 返回 200
- [ ] 12 个 LDAP 用户已导入，4 个组及成员正确
- [ ] `dev01` 密码模式取 token，`groups=['developers']`
- [ ] GitLab：登录页有「Keycloak 统一登录」，dev01 登录成功且 identity 有 `openid_connect`
- [ ] Jenkins：`commenceLogin` 303，dev01 登录成功，`whoAmI` 含 `developers`；`breakglass` 应急登录可用
- [ ] Harbor：`systeminfo.auth_mode=oidc_auth`，`/c/oidc/login` 302，dev01 登录后非管理员
- [ ] ArgoCD：dev01 `loggedIn:true, groups=['developers']`；dev01 403 / lead01 404 的 RBAC 差异成立
- [ ] SonarQube：登录页有「Log in with Keycloak」，dev01 登录成功，组同步生效
- [ ] Artifactory：LDAP Test connection 成功，LDAP 账号可登录，本地 `admin` 仍可登录（内部密码登录未被禁）
- [ ] 四个服务各自保留一个本地应急入口（Jenkins `breakglass`、Harbor 本地 admin、GitLab root+2FA、ArgoCD 本地 admin）
- [ ] 清理排障残留（第 9 节）

---

## 9. 清理与收尾（对接完成后必须做）

1. **移除 Keycloak DEBUG 日志**（排障残留，日志量很大）：
   ```bash
   kubectl -n keycloak set env deploy/keycloak KC_LOG_LEVEL- 
   kubectl -n keycloak rollout status deploy/keycloak --timeout=180s
   ```
   同时把 `manifests/keycloak/10-deployment.yaml` 里的镜像改成 `.../library/keycloak:26.6`、删掉 `KC_LOG_LEVEL=DEBUG`，让清单与集群一致。
2. **移除 GitLab 临时调试补丁**（曾为抓堆栈插入 `[OIDC-DEBUG]` 日志）：
   ```bash
   cp /root/omniauth_controller.bak \
      /opt/gitlab/embedded/service/gitlab-rails/app/controllers/omniauth_callbacks_controller.rb
   gitlab-ctl restart puma
   ```
3. **ArgoCD 日志级别回默认**：
   ```bash
   kubectl -n argocd get cm argocd-cmd-params-cm -o json | python3 -c '...'  # 删掉 server.log.level=debug
   kubectl -n argocd rollout restart deploy/argocd-server
   ```
4. 关闭不需要的客户端能力：`gitlab/jenkins/harbor/argocd-dex` 四个 client 的 `directAccessGrantsEnabled` 已设为 `false`（密码模式统一由 `cli-test` 承担；排障时若开过要关回去）。
   ```bash
   bash scripts/keycloak/431-harden-clients.sh   # gitlab/harbor 关闭口令模式，并创建 cli-test
   bash scripts/keycloak/432-disable-jenkins-token.sh
   ```

---

## 9.5 2026-11-27 附：Harbor / ArgoCD 登录报 `Invalid parameter: redirect_uri` 的完整修法

### 症状

在 `https://harbor.corp.local` 或 `https://argocd.corp.local` 点「用 Keycloak 登录」，Keycloak 直接甩一个没有登录框的错误页：

```
We are sorry...
Invalid parameter: redirect_uri
```

### 先取证，别改配置（三条硬事实）

```bash
# 1) 应用实际发出的 redirect_uri 是什么
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login | grep -i '^location'
curl -s -o /dev/null -D - -k "https://argocd.corp.local/api/dex/auth/keycloak?client_id=argo-cd&redirect_uri=https%3A%2F%2Fargocd.corp.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=x" | grep -i '^location'

# 2) Keycloak 里对应 client 注册的回调是什么
kubectl -n keycloak exec <pod> -- /bin/sh -c '
  KC=/opt/keycloak/bin/kcadm.sh
  $KC config credentials --server http://localhost:8080 --realm master --user admin --password "${KEYCLOAK_ADMIN_PASS}" >/dev/null
  for c in harbor argocd argocd-dex; do
    echo "--- $c"
    $KC get clients -r corp -q clientId=$c --fields clientId,redirectUris --format csv --noquotes
  done'
```

实测结果（**2026-11-26 复现时的原始状态，现已全部按上表切成 https**，保留此表用于理解排障过程）：

| 应用 | 实发 `redirect_uri` | Keycloak 注册 | 结论 |
|---|---|---|---|
| Harbor | `http://192.168.200.12:30090/c/oidc/callback` | `https://harbor.corp.local/c/oidc/callback` | 应用侧发错 |
| ArgoCD | `https://argocd.corp.local/api/dex/callback` | `argocd`=`…/auth/callback`；`argocd-dex`=`http://192.168.200.12:30080/api/dex/callback` | 改错了 client |

### 修法一：ArgoCD（改 `argocd-dex`，不是 `argocd`）

```bash
kubectl -n keycloak exec <pod> -- /bin/sh -c '
  KC=/opt/keycloak/bin/kcadm.sh
  $KC config credentials --server http://localhost:8080 --realm master --user admin --password "${KEYCLOAK_ADMIN_PASS}" >/dev/null
  ID=$($KC get clients -r corp -q clientId=argocd-dex --fields id --format csv --noquotes | tail -1)
  $KC update clients/$ID -r corp \
    -s "redirectUris=[\"https://argocd.corp.local/api/dex/callback\",\"http://192.168.200.12:30080/api/dex/callback\"]" \
    -s "webOrigins=[\"https://argocd.corp.local\",\"http://192.168.200.12:30080\"]"'
```

> 保留旧 http 回调是为了回滚窗口期还能用；稳定后可以只留 https 一条。

### 修法二：Harbor（`EXT_ENDPOINT` 必须改 https）

Harbor 的回调绝对地址**由 `EXT_ENDPOINT` 拼出来**，跟浏览器从哪个入口进来无关。所以只改 Keycloak 里注册的回调没用，必须把 `EXT_ENDPOINT` 一起改成 `https://harbor.corp.local`：

```bash
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'     # 改前应为 http://192.168.200.12:30090
# 用 kubectl edit / replace 改 CM，然后
kubectl -n harbor rollout restart deploy/harbor-core
kubectl -n harbor rollout status  deploy/harbor-core --timeout=120s
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login | grep -o 'redirect_uri=[^&]*'
# 期望：redirect_uri=https%3A%2F%2Fharbor.corp.local%2Fc%2Foidc%2Fcallback
```

### 但 `EXT_ENDPOINT=https` 会把「按 IP 拉镜像」打断（必须一起处理）

改完立刻验证 registry 的 token realm：

```bash
curl -s -i http://192.168.200.12:30090/v2/ | grep -i www-authenticate
# realm 变成 https://192.168.200.12:30090/service/token —— 而这个端口是明文 http
```

后果：`podman login 192.168.200.12:30090`、Jenkins 的 Jib 推送、kubelet 按 `192.168.200.12:30090/...` 拉镜像全部报
`http: server gave HTTP response to HTTPS client` / `no basic auth credentials`。本轮做了三处配套修改：

1. **containerd 侧别名**（让老镜像名继续能用，避免改 20+ 份静态清单）：
   ```bash
   mkdir -p /etc/containerd/certs.d/192.168.200.12:30090 /etc/containerd/certs.d/harbor.corp.local
   cat > /etc/containerd/certs.d/192.168.200.12:30090/hosts.toml <<'EOF'
   server = "https://harbor.corp.local"
   [host."https://harbor.corp.local"]
     capabilities = ["pull", "resolve"]
     ca = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
   EOF
   cat > /etc/containerd/certs.d/harbor.corp.local/hosts.toml <<'EOF'
   server = "https://harbor.corp.local"
   [host."https://harbor.corp.local"]
     capabilities = ["pull", "resolve", "push"]
     ca = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
   EOF
   systemctl restart containerd
   crictl pull harbor.corp.local/library/<任意公共镜像>:tag      # 验证 CA 生效
   ```
2. **CI（GitLab）**：`HARBOR_REGISTRY` 变量改 `harbor.corp.local`；`ci/verify-image.sh` 里的 `http://$reg` 改 `https://$reg`（runner 是宿主进程，已 update-ca-trust，无需 `-k`）。
3. **Jenkins**：共享库 `Defaults.groovy` / `buildAndPushImage.groovy` / demo-maven 的 `Jenkinsfile`、`pom.xml` 里的 Harbor 地址改域名；Jib 走 https 依赖 **JVM cacerts**，必须确认 keystore 里真有内部 CA：
   ```bash
   kubectl -n jenkins exec <pod> -c jenkins -- sh -c 'keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit | grep -i corp-internal-ca'
   ```
   > 注意：容器里的 **curl 用系统 CA store**，没装内部 CA，所以共享库里校验 manifest 的 curl 加了 `-k`；Jib 走 JVM keystore，不受影响。

### 验收（脚本可复用）

```bash
bash scripts/gateway/510-redirect-debug.sh     # 打印 7 个 client 的注册回调 + Harbor/ArgoCD 实发回调
bash scripts/gateway/512-authorize-check.sh    # 两个入口都应「已进入 Keycloak 登录页」而不是 Invalid parameter
bash scripts/gateway/527-sso-e2e.sh            # 建临时用户走完整登录，验完自动删
```

`527-sso-e2e.sh` 的成功输出（本轮实测）：

```
Harbor: 最终 200 @ https://harbor.corp.local/      cookies = [sid, KEYCLOAK_SESSION …]
ArgoCD: 最终 200 @ https://argocd.corp.local/      cookies = [argocd.token, KEYCLOAK_SESSION …]
```

---

### 9.6 附：Harbor 登录报 `failed to create user record: user xxx or email xxx already exists`

完整报文（浏览器看是 `HTTP 500` + JSON）：

```json
{"errors":[{"code":"UNKNOWN","message":"failed to create user record: user legacy1 or email legacy1@corp.local already exists"}]}
```

**根因**：Harbor 里已经有一条同名/同邮箱的**本地数据库用户**记录（切 `oidc_auth` 之前用 db_auth 或 LDAP 建过的）。`oidc_auto_onboard=true` 首次 OIDC 登录要"建用户"，撞上旧记录就直接 500。注意：**`auth_mode=oidc_auth` 之后本地记录根本登录不了**（Harbor 只放行 OIDC 和 admin），所以它就是一条死记录，删掉没有功能损失。

**处理步骤**（先看再删）：

```bash
# 1) 找到冲突记录（username 或 email 命中即可）
curl -s -k -u 'admin:${HARBOR_ADMIN_PASS}' \
  'https://harbor.corp.local/api/v2.0/users?page_size=100' | python3 -c '
import sys,json
for u in json.load(sys.stdin):
    if "legacy1" in (u["username"] or "") or "legacy1" in (u.get("email") or ""):
        print(u["user_id"], u["username"], u.get("email"), u.get("creation_time"))'

# 2) 记一下它有没有项目成员身份（删用户会连带丢角色，之后要靠 OIDC 重新加）
curl -s -k -u 'admin:${HARBOR_ADMIN_PASS}' 'https://harbor.corp.local/api/v2.0/projects?page_size=100' | python3 -c '
import sys,json,subprocess
for p in json.load(sys.stdin):
    out=subprocess.check_output(["curl","-s","-k","-u","admin:${HARBOR_ADMIN_PASS}",
        f"https://harbor.corp.local/api/v2.0/projects/{p[\"name\"]}/members?page_size=100"]).decode()
    for m in json.loads(out or "[]"):
        if m.get("entity_name")=="legacy1": print(p["name"], m.get("role_name"))'

# 3) 删除该本地用户（id 用第 1 步查到的）
curl -s -k -u 'admin:${HARBOR_ADMIN_PASS}' -o /dev/null -w '%{http_code}\n' \
  -X DELETE 'https://harbor.corp.local/api/v2.0/users/11'
```

删完**再登录一次即可**：OIDC 会重新建用户（`oidc_auto_onboard=true`），项目角色按需在 Harbor UI → 项目 → 成员里重新加。

> 本轮实测：`legacy1`(id=11，2026-11-25 建) 无任何项目成员身份，删除后记录清空；`dev01`(id=12) 同样是无角色的历史本地记录，目前不影响任何人登录，等它首次 SSO 时如报同一错误，用第 3 步同样处理即可。
> 排查时顺手发现上一轮 SSO 探针在 Harbor 留下了一条 `sso-probe` 记录（Keycloak 侧已删、Harbor 侧不会自动删），已一并清理——以后用临时用户做登录验证，两边都要删。

---

## 10. 故障速查表（症状 → 原因 → 修法）

| 症状 | 根因 | 修法 |
|---|---|---|
| LDAP 同步 400 / 导入 0 用户，`testLDAPConnection` 却 204 | 组件 `parentId` 写成 realm 名 | 改成 realm UUID（4.2） |
| `400 Cannot parse the JSON`（PUT 组件） | `config` 用了纯字符串 | 必须多值数组 `["v"]` |
| `GET /components?type=` 查不到组件 | 该过滤参数不生效 | 拉全量后本地过滤 |
| Keycloak 26.4 同步报 `UnknownError` | 26.4.x 已知 bug | 升到 26.6.x |
| 服务报 `Missing parameter: code_challenge_method` | 客户端开了 PKCE，但该客户端不发 challenge | `pkce.code.challenge.method` 设空串 |
| Keycloak 属性删不掉 | 删 key 不生效 | 显式设空字符串 |
| GitLab `SSL_connect wrong version number` | `discovery:true` 走 HTTPS | `discovery:false` + `scheme:http` |
| GitLab `include?' for nil` | endpoint 用了相对路径 | 改绝对 URL |
| GitLab「邮箱已存在」 | 未开启邮箱自动关联 | `omniauth_auto_link_user = true` |
| Jenkins 403 `No valid crumb` | crumb 与会话不配套 | 用同一 cookie jar 取 crumb 再提交 |
| Jenkins reload 后 realm 没变 | ConfigMap 挂载同步延迟 | 等 60s 再 reload 一次 |
| Jenkins JCasC 报未知符号 | 用了 `oicAuth` | 正确符号是 `oicSecurityRealm` |
| Harbor 拒绝切 auth_mode | 库里已有非本地用户 | 先删用户再 PUT（7.3） |
| Harbor 400 auth_mode 非法 | 写了 `oidc` | 必须 `oidc_auth` |
| ArgoCD CrashLoop `configmap not found` | apply 覆盖把 cm 标签清了 | 补 `app.kubernetes.io/*` 标签 |
| ArgoCD `failed to verify id token signature` | ArgoCD 直连验签兼容问题 | 改 Dex 桥接（7.4） |
| ArgoCD `no id_token in token response` | `requestedScopes` 漏 `openid` | 至少含 `openid profile email groups` |
| ArgoCD `Invalid redirect URL` | `return_url` 用了相对路径 | 传绝对 URL |
| Harbor / ArgoCD 报 `Invalid parameter: redirect_uri` | 注册的 redirectUri ≠ 应用实发 | 见 §9.5（Harbor 改 `EXT_ENDPOINT`，ArgoCD 改 `argocd-dex`） |
| Harbor 报 `failed to create user record: user ... already exists` | Harbor 里残留同名/同邮箱的本地用户 | 查 `GET /api/v2.0/users` → `DELETE /api/v2.0/users/<id>` 后重登（§9.6） |
| 改 `EXT_ENDPOINT=https` 后 push/pull 报 `HTTP response to HTTPS client` | registry 的 token realm 变成了 `https://<IP>:30090`，端口是明文 | 见 §9.5 的三处配套（containerd 别名 / CI 变量 / Jib 域名） |
| 模拟登录回调 `Invalid 'state'` | cookie 域前后不一致 | 全程用同一个 host（`192.168.200.12`） |

---

## 11. 回滚手册

| 服务 | 备份位置 | 回滚动作 |
|---|---|---|
| GitLab | `/root/gitlab.rb.bak-<时间>` | `cp 备份 /etc/gitlab/gitlab.rb && gitlab-ctl reconfigure` |
| Jenkins | `/root/jenkins-sso-bak-<时间>.yaml` | `kubectl apply -f 备份`，等 60s 后 `scripts/jenkins/338-reload-casc.sh` |
| Harbor | `/root/harbor-cfg-bak-<时间>.json` | `PUT /api/v2.0/configurations` 把 `auth_mode` 改回 `db_auth`（必要时先删 OIDC 用户） |
| ArgoCD | `/root/argocd-oidc-bak-<时间>-{cm,rbac}.yaml` | `kubectl apply -f` 两个备份 → `rollout restart deploy/argocd-server deploy/argocd-dex-server` → 补 cm 标签 |
| Keycloak | Postgres PVC `/data/keycloak/pg` | 停 deploy 后从 `/data/keycloak` 的备份目录恢复数据库；或直接删 realm 重建 |

> 回滚 Harbor 时同样受“库里已有 OIDC 用户则不能改 auth_mode”的限制，必要时先用本地 admin 删掉这批用户。

---

## 12. 脚本索引（全部在 `C:\Users\morning\Desktop\cicd`）

| 用途 | 脚本 |
|---|---|
| Keycloak 建 scope + 4 个 client（幂等） | `scripts/keycloak/416-create-clients.sh` |
| 修正组件 parentId + 触发全量同步 | `scripts/keycloak/422-fix-parentid.sh` |
| 建组映射器 + 同步 + 打印成员 | `scripts/keycloak/423-group-mapper.sh` |
| 密码模式验证 token/groups（早期手段，已被 PKCE 关闭取代） | 已归档 |
| Keycloak 升级镜像（历史） | 已归档 |
| 清 PKCE（gitlab/jenkins/argocd，历史） | 已归档（当前客户端已不带 PKCE 要求） |
| 建 argocd-dex 客户端 | `scripts/keycloak/429-argocd-dex-client.sh` |
| 收敛客户端权限（关闭口令模式 + 建 cli-test） | `scripts/keycloak/431-harden-clients.sh`、`432-disable-jenkins-token.sh` |
| GitLab 切 OIDC / 改绝对端点 / 自动关联 | `scripts/gitlab/041-switch-oidc.sh`（端点与自动关联已写入最终 gitlab.rb，无需再跑调试脚本） |
| GitLab 端到端模拟登录 | `scripts/gitlab/080-final-e2e.sh` |

| Jenkins 下发 JCasC + reload | `scripts/jenkins/336-switch-oidc.sh`、`338-reload-casc.sh` |
| Jenkins 应急账号验证 | 表单 POST `securityRealm/escapeHatch`（见 12.3） |
| Harbor 切换 OIDC | `scripts/harbor/512-switch-oidc.sh`、`515-verify-oidc.sh` |
| ArgoCD 切 Dex 桥接 / 开 groups | `scripts/argocd/237-switch-dex-bridge.sh`、`238-dex-enable-groups.sh` |
| ArgoCD 验签失败排障（历史取证链，已归档） | 结论见第 6 节：走 Dex 桥接 |
| 一键验证（ArgoCD/Jenkins/Harbor） | `scripts/verify/900-e2e-three.sh`、`926-dex-e2e.sh`、`928-dex-groups.sh`、`932-rbac-final.sh` |
| 导出当前全部 SSO 配置 | `scripts/verify/950-dump-configs.sh` |

---

## 13. 待决策 / 已知风险（2026-11-26 现状）

1. **全链路仍是 HTTP 明文**：Keycloak（`KC_HOSTNAME_STRICT=false`）、GitLab、Harbor、Sonar、Artifactory、Jenkins 全部 http，OIDC 回调与 CI 令牌都在明文里跑；LDAP 也是 389 无 TLS。生产要上 TLS，且要一并改 6 个系统的 issuer/回调地址，属于成套变更。
2. **Harbor 只支持组过滤、不做角色映射**：管理员靠本地 admin 或 `oidc_admin_group`（当前 `platform-admins`）。
3. **GitLab 历史 LDAP 用户迁移**：依赖 `auto_link_user=true` 按邮箱关联；若邮箱不唯一需用 rails 批量写 `identities`。
4. **Artifactory 组权限未映射**：OSS 无 `/api/security/groups` REST，只能用 UI 建组 + permission target；当前所有能登录的 LDAP 用户对 `build-artifacts` 的实际权限尚未按组收敛。
5. **Sonar 本地管理员切换**：`sonaradmin` 是新建的本地管理员，原 `admin` 的密码仍未知、CI 令牌挂在 `admin` 名下不可删；待用 `sonaradmin` 登录后重置 `admin` 或彻底弃用。
6. **LDAP 目录有越权遗留**：`cn=遗留账号1`（uid `legacy1`）同时属于 `platform-admins` 与 `developers`，另有 `cn=test` 越界组。经 Keycloak 会把管理员权限带给 GitLab/Harbor/Jenkins/Sonar/ArgoCD（详见 `03-身份与账号/OpenLDAP目录.md` 2.3）。
7. **单点 Keycloak**：Keycloak 或 PG 一旦不可用，**六个系统的网页登录同时失效**（已登录 token 按有效期继续）。当前无副本、无健康告警。
8. **OIDC 客户端未收口令模式**：`431-harden-clients.sh` 已收敛部分 client，`artifactory` client 建了但未使用，建议删掉减少攻击面。
