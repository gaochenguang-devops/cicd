# OpenLDAP 统一账号与权限管理（192.168.200.12）

> **当前形态（2026-11-26 实测）**：LDAP 是唯一账号源，登录链路为 **LDAP → Keycloak(realm `corp`) → 各系统 OIDC**。GitLab（`ldap_enabled=false`，只走 `openid_connect`）、Harbor（`auth_mode=oidc_auth`）、Jenkins（`oicSecurityRealm`）、Sonar、ArgoCD（Dex `oidc` connector）全部经 Keycloak；**只有 Artifactory 仍直连 LDAP**（OSS 版无 OIDC）。
> 目录实际有 **12 个账号、4 个标准组**（另有历史遗留的 `cn=test` 组与 2 个 `cn=` 形式的非标准账号，见 2.3）。本文第 3 节的目录/overlay/管理界面仍是当前实现；第 4、5 节的"直连配置"已不是生效路径，保留作为历史与对照，生效配置见 `03-身份与账号/统一身份SSO-Keycloak.md`。

一套 LDAP 目录给全部业务系统提供认证与**组级权限**来源：4 个组、12 个账号，组内角色决定 GitLab/Harbor/ArgoCD/Sonar 的权限等级。现状核对用 `scripts\sonar-jfrog\1120-ldap-dump.sh`（账号/组全量导出）与 `1123-users-check.sh`（GitLab 用户 + Harbor 成员），OIDC 部分见 `03-身份与账号/统一身份SSO-Keycloak.md` 的验证清单。

## 1. 整体结构（当前）

```
                    ┌──────────────────────────────┐
   账号 / 组  ──────▶│ OpenLDAP 192.168.200.12:389  │
                    │ dc=corp,dc=local             │
                    │  ou=people  inetOrgPerson     │
                    │  ou=groups  4 个 groupOfNames │
                    └──────────────┬───────────────┘
                                   │ LDAP 联邦（READ_ONLY，corp-ldap 组件）
                                   ▼
                    ┌──────────────────────────────┐
                    │ Keycloak :30087  realm corp   │
                    │ 12 用户 / 4 组 / 组 claim=groups│
                    └──┬────────┬────────┬─────────┬┘
            OIDC       │        │        │         │
        ┌──────────────┘        │        │         └──────────────┐
        ▼                       ▼        ▼                        ▼
  GitLab :80            Harbor :30090  Jenkins :30088      Sonar :30091
  openid_connect        oidc_auth      oicSecurityRealm    authoidc
  （LDAP 已关闭）        （组→项目角色）  （组→矩阵）          （组→admin/scan）
                                   │
                                   │ ArgoCD :30080 走 Dex（oidc connector → Keycloak）
                                   ▼
                         Artifactory :30092 —— 唯一 LDAP 直连（corp-ldap）
```

| 项 | 值 |
|---|---|
| LDAP 地址 | `ldap://192.168.200.12:389`（仅明文 389，未启用 636/TLS） |
| Base DN | `dc=corp,dc=local` |
| 管理员 | `cn=admin,dc=corp,dc=local` / `${LDAP_ADMIN_PASS}` |
| 用户 OU | `ou=people,dc=corp,dc=local` |
| 组 OU | `ou=groups,dc=corp,dc=local` |
| 用户初始密码 | `${LDAP_USER_INIT_PASS}`（`{SSHA}` 存储） |
| 部署形态 | podman 容器 + systemd quadlet，镜像 `192.168.200.12:30090/apps/openldap:1.5.0` |
| 数据目录 | `/data/openldap/data`、`/data/openldap/config` |
| 管理界面 | phpLDAPadmin http://192.168.200.12:8090（`cn=admin` / `${LDAP_ADMIN_PASS}`） |

## 2. 账号与组（实测）

### 2.1 标准账号（10 个，`uid=…,ou=people`）

| uid | 姓名 | 邮箱 | uidNumber | 所属组 |
|---|---|---|---|---|
| lead01 | 李平台 | lead01@corp.local | 10010 | platform-admins |
| ops01 | 张运维 | ops01@corp.local | 10011 | devops |
| ops02 | 王运维 | ops02@corp.local | 10012 | devops |
| dev01 | 陈开发 | dev01@corp.local | 10013 | developers |
| dev02 | 刘开发 | dev02@corp.local | 10014 | developers |
| dev03 | 赵开发 | dev03@corp.local | 10015 | developers |
| dev04 | 孙开发 | dev04@corp.local | 10016 | developers |
| dev05 | 周开发 | dev05@corp.local | 10017 | developers |
| qa01 | 吴测试 | qa01@corp.local | 10018 | qa |
| qa02 | 郑测试 | qa02@corp.local | 10019 | qa |

条目类型 `inetOrgPerson + posixAccount`，属性含 `uid / cn / sn / givenName / displayName / mail / uidNumber / gidNumber / homeDirectory / loginShell / userPassword`。

### 2.2 组（4 个标准组）

| cn | 成员 | 语义 | 对应权限（GitLab / Harbor / ArgoCD / Sonar） |
|---|---|---|---|
| `platform-admins` | lead01（实况还含非标准账号，见 2.3） | 平台管理员 | 实例管理员 / 系统管理员 / admin / Sonar admin |
| `devops` | ops01, ops02 | 运维 | maintainer / maintainer / admin / Sonar admin |
| `developers` | dev01–dev05（实况还含 2 个非标准账号） | 开发 | developer / developer / readonly / Sonar scan |
| `qa` | qa01, qa02 | 测试 | reporter / guest / readonly / Sonar scan |

### 2.3 非标准条目（2026-11-26 实测发现，需清理）

目录里除 10 个标准账号外，还有 **2 个通过 phpLDAPadmin 手工建的账号**，DN 是 `cn=` 而不是 `uid=`，且 uidNumber 落在 1000/1001：

| DN | uid | 所属组 | 问题 |
|---|---|---|---|
| `cn=遗留账号1,ou=people,dc=corp,dc=local`（LDAP 里以 UTF-8 base64 存储） | legacy1 | platform-admins、developers、`cn=test` | **普通个人账号同时拥有平台管理员权限**；DN 形态不符合 `uid=…` 约定 |
| `cn=legacy2,ou=people,dc=corp,dc=local`（cn 含空格，同样 base64 存储） | legacy2 | developers | DN 含空格，Keycloak/LDAP 查询易失配；mail 用的是外部 163 邮箱 |

另有 `cn=test,dc=corp,dc=local`（`groupOfNames`，挂在 Base 下而非 `ou=groups`，成员只有上面那位）。这些条目**已被 Keycloak 同步导入**（realm 内 12 个用户即 10+2）。

建议处理（不影响现有登录）：

```bash
# 1) 先确认这两个人的真实归属，再决定保留/删除
ldapsearch -x -H ldap://192.168.200.12:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' \
  -b ou=people,dc=corp,dc=local "(uid=legacy1)" dn cn memberOf

# 2) 若只是临时测试账号：从 platform-admins 移除成员（务必先移权限，再决定是否删条目）
ldapmodify -x -H ldap://192.168.200.12:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' <<'EOF'
dn: cn=platform-admins,ou=groups,dc=corp,dc=local
changetype: modify
delete: member
member:: Y2495pmo5YWJIOmrmCxvdT1wZW9wbGUsZGM9Y29ycCxkYz1sb2NhbA==
EOF
```

> 后续建号一律用 `ldap-add-user.sh`（生成 `uid=…` DN）或手册里的模板，不要用 phpLDAPadmin 默认 `cn=` 模板，避免再出现这类不一致。

### 2.4 权限矩阵（各系统实测）

| 组 | Harbor（`apps`） | GitLab（组 + `podinfo`） | ArgoCD（`argocd-rbac-cm`） | Sonar（组授权） |
|---|---|---|---|---|
| platform-admins | 系统管理员 | 实例管理员 + maintainer | `admin` | `admin` |
| devops | maintainer | maintainer | `admin` | `admin` |
| developers | developer | developer | `readonly` | `scan` |
| qa | guest | reporter | `readonly` | `scan` |

依据：Harbor 组继承由 `memberOf` overlay 驱动（见 3.3）；GitLab 侧由 `ldap-gitlab-sync.timer` 每 10 分钟同步建号并赋角色（见 5.6，脚本仍在跑，只是登录改走 OIDC）；ArgoCD 侧 `policy.csv` 按 Keycloak `groups` claim 判定；Sonar 侧按 OIDC 组映射到 `platform-admins/devops`=admin、`developers/qa`=scan。

实测判定依据（`scripts\sonar-jfrog\1120-ldap-dump.sh` + `1121-ldap-people.sh`）：

```
dev01  current=200 projects=apps,library     # Harbor 认证 + 组继承
lead01 current=200 projects=apps,library     # 管理员组生效
lead01 login=302 dashboard=200 project_edit=200   # GitLab maintainer
ops01  login=302 dashboard=200 project_edit=200   # GitLab maintainer
dev01  login=302 dashboard=200 project_edit=404   # developer 无设置权限
qa01   login=302 dashboard=200 project_edit=404   # reporter 只读
```

## 3. OpenLDAP 部署

### 3.1 镜像与容器

镜像从 daocloud 拉取后推进 Harbor 统一管理（bitnami 版本拉取失败，改用 osixia）：

```bash
podman pull docker.m.daocloud.io/osixia/openldap:1.5.0
podman tag  docker.m.daocloud.io/osixia/openldap:1.5.0 192.168.200.12:30090/apps/openldap:1.5.0
podman push 192.168.200.12:30090/apps/openldap:1.5.0    # 需先 podman login Harbor
```

`/etc/containers/systemd/openldap.container`：

```ini
[Unit]
Description=OpenLDAP
After=network-online.target

[Container]
Image=192.168.200.12:30090/apps/openldap:1.5.0
ContainerName=openldap
PublishPort=389:389
Volume=/data/openldap/data:/var/lib/ldap:Z
Volume=/data/openldap/config:/etc/ldap/slapd.d:Z
Environment=LDAP_ORGANISATION=Corp
Environment=LDAP_DOMAIN=corp.local
Environment=LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASS}
Environment=LDAP_TLS=false
Environment=LDAP_REMOVE_CONFIG_AFTER_SETUP=false

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl start openldap
podman ps --filter name=openldap     # slapd 2.4.57 起来即成功
```

### 3.2 目录数据

`ou=people` / `ou=groups` 与 10 用户、4 组由 `scripts\ldap\122-ldap-data.sh` 生成 LDIF 并 `ldapadd` 导入。

**踩坑：密码为空**。首次导入用 `slappasswd` 生成哈希，但该命令不在 `openldap-clients` 包里（`set -u` 下变量为空），导入后 `userPassword:` 空值，全部账号 `Invalid credentials (49)`。改用 Python 生成 SSHA 并用 `ldapmodify` 批量回填：

```python
# {SSHA} = base64( sha1(password + salt) + salt )
h = hashlib.sha1(pw.encode() + salt).digest() + salt
"{SSHA}" + base64.b64encode(h).decode()
```

**踩坑：批量 LDIF 用 `---` 分隔导致 0 成功**。`ldapmodify` 不接受 `---` 作条目分隔，去掉后条目间仅留空行，10 条全部成功。

### 3.3 memberof overlay（Harbor 组继承的关键）

Harbor 判定用户所属组读的是 **`memberOf`** 属性（debug 日志 `Membership attribute: memberof`），而 OpenLDAP 默认不生成该属性。必须在 `olcDatabase={1}mdb,cn=config` 上加载 `memberof` + `refint`：

```ldif
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: memberof.la
olcModuleLoad: refint.la
```

```ldif
dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf
```

注意两点：overlay 条目必须写 `changetype: add`（否则报 `modify operation type is missing`）；已有组需要 `replace: member` 触发一次重算，`memberOf` 才会生成。当前 `cn=config` 里存在重复的 `memberof/refint` overlay（`{0}`、`{1}`、`{2}`、`{3}`），功能正常，未清理。

验证：

```bash
ldapsearch -x -H ldap://192.168.200.12:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' \
  -b ou=people,dc=corp,dc=local -LLL "(uid=dev01)" memberOf
```

### 3.4 Web 管理界面（phpLDAPadmin）

OpenLDAP 本身不带 Web UI，需要第三方前端。本环境已部署 **phpLDAPadmin**（osixia 镜像，podman quadlet，systemd 托管）：

| 项 | 值 |
|---|---|
| 地址 | **http://192.168.200.12:8090** |
| 登录 DN | `cn=admin,dc=corp,dc=local` |
| 密码 | `${LDAP_ADMIN_PASS}` |
| 容器 | `phpldapadmin`（监听 80，映射 8090；`/etc/containers/systemd/phpldapadmin.container`） |

在界面里可以直接浏览 `dc=corp,dc=local` 树、新增/修改用户与组、改密码（`userPassword` 用明文自动转 SSHA）。

容器可达性验证（实测 2026-11-26）：

```
admin_bind=OK
user_count=12      # 10 个标准 uid + 2 个 cn= 形式的遗留账号
group_count=4      # ou=groups 下；另有 cn=test,dc=corp,dc=local 不在此列
```

> 用 phpLDAPadmin 建号时**不要用默认的 `cn=…` 模板**，它会把 DN 建成 `cn=姓名,ou=people`，与 `uid=…` 体系不一致（2.3 就是这类产物）。请用 `ldap-add-user.sh` 或手册里的 `uid` 模板。

其他可选前端：LDAP Account Manager（LAM，功能更全，支持模板与自助改密）、Self Service Password（只做用户自助改密，适合给普通员工开放）。当前只选了 phpLDAPadmin，够日常运维用。

## 4. Harbor 对接

> **当前不再直连**：`auth_mode=oidc_auth`（Keycloak client `harbor`，groups claim 为 `groups`，auto onboard 开，token 30 min）。下面 4.1 的 `ldap_auth` 参数是 11-25 的历史配置，保留作为回退方案与字段对照；**不要再按本节执行 `PUT`**，会把 Harbor 从 OIDC 切回 LDAP。回退步骤见 `03-身份与账号/统一身份SSO-Keycloak.md` 的"回退"小节。

### 4.1 认证参数（历史：`PUT /api/v2.0/configurations`）

| 键 | 值 |
|---|---|
| `auth_mode` | `ldap_auth` |
| `ldap_url` | `ldap://192.168.200.12:389` |
| `ldap_base_dn` | `dc=corp,dc=local` |
| `ldap_search_dn` | `cn=admin,dc=corp,dc=local` |
| `ldap_search_password` | `${LDAP_ADMIN_PASS}` |
| `ldap_uid` | `uid` |
| `ldap_scope` | `2`（subtree） |
| `ldap_group_base_dn` | `ou=groups,dc=corp,dc=local` |
| `ldap_group_search_filter` | `(objectClass=groupOfNames)` |
| `ldap_group_attribute_name` | `cn` |
| `ldap_group_attribute_is_dn` | `true` |
| `ldap_group_admin_dn` | `cn=platform-admins,ou=groups,dc=corp,dc=local` |

切换顺序：先 `POST /api/v2.0/ldap/ping` 返回 `{"success":true}`，再 `PUT /api/v2.0/configurations`，最后读回 `auth_mode` 确认已变 `ldap_auth`。

### 4.2 项目成员（组级权限）

`apps` 项目成员现状（2026-11-26 `GET /api/v2.0/projects/apps/members` 实测）：

| 成员 | 类型 | 角色 |
|---|---|---|
| admin | 本地用户 | projectAdmin |
| developers | LDAP 组 | developer |
| devops | LDAP 组 | maintainer |
| qa | LDAP 组 | guest |

（早期为验证组继承手工加的 `dev01` 个人成员已不在列表中，只剩四个组/管理员，符合预期。）

添加组必须使用整数类型：

```bash
curl -u admin:${HARBOR_ADMIN_PASS} -X POST \
  http://192.168.200.12:30090/api/v2.0/projects/apps/members \
  -H 'Content-Type: application/json' -d '{
    "role_id": 2,
    "member_group": {
      "group_name": "developers",
      "group_type": 1,
      "ldap_group_dn": "cn=developers,ou=groups,dc=corp,dc=local"
    }
  }'
```

**踩坑**：`group_type` 传字符串 `"ldap"` 会 422（`cannot unmarshal string into Go struct field ... group_type of type int64`）。取值 `1=LDAP 组`、`2=HTTP 组`、`3=OIDC 组`；`role_id` 为 `1=projectAdmin`、`2=developer`、`3=guest`、`4=maintainer`。

### 4.3 认证验证方式

Harbor 网页登录走 `/c/login` 需要 CSRF token，脚本化验证改用 Basic Auth：

```bash
curl -u dev01:'${LDAP_USER_INIT_PASS}' http://192.168.200.12:30090/api/v2.0/users/current
# 200，返回体带 "comment":"from LDAP." 与中文 realname
curl -u dev01:'wrong' ...           # 401
```

组继承生效后，`GET /api/v2.0/projects` 对 dev/ops/qa/lead 均返回 `apps,library`。

## 5. GitLab 对接

> **当前已关闭直连**（2026-11-26）：`/etc/gitlab/gitlab.rb` 里 `gitlab_rails['ldap_enabled'] = false`（文件里还留着一行 `= true` 在其上方，**生效的是最后一行 false**；清理时把 true 那行删掉更安全），登录只走 `openid_connect`（provider `openid_connect`，label「Keycloak 统一登录」）。下面 5.1~5.3 是 11-25 直连时代的配置与实测记录，保留作回退参考；5.4~5.6 讲组同步与权限映射，**这部分仍在生效**（`ldap-gitlab-sync.timer` 每 10 分钟跑一次）。

### 5.1 配置（历史：`/etc/gitlab/gitlab.rb` 的 LDAP 块）

```ruby
gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = {
  'main' => {
    'label'                => 'Corp LDAP',
    'host'                 => '192.168.200.12',
    'port'                 => 389,
    'uid'                  => 'uid',
    'bind_dn'              => 'cn=admin,dc=corp,dc=local',
    'password'             => '${LDAP_ADMIN_PASS}',
    'encryption'           => 'plain',
    'active_directory'     => false,
    'allow_username_or_email_login' => true,
    'block_auto_created_users'      => false,
    'base'                 => 'dc=corp,dc=local',
    'user_filter'          => '(objectClass=inetOrgPerson)',
    'attributes'           => {
      'username' => 'uid', 'email' => 'mail', 'name' => 'cn',
      'first_name' => 'givenName', 'last_name' => 'sn'
    }
  }
}
```

```bash
gitlab-ctl reconfigure      # 约 14 s
gitlab-rake gitlab:ldap:check   # LDAP authentication... Success，当时列出 10 个用户（现 12 个）
```

注意：provider id 由块名派生，这里是 **`ldapmain`**（不是 `main`）。`gitlab-rails runner` 里用 `Gitlab::Auth::Ldap::Config.new("main")` 会抛 `InvalidProvider: Unknown provider (main). Available providers: ["ldapmain"]`。关掉 LDAP 后 `ldapmain` 仍在数据库用户记录里（`provider=ldapmain`），只是不再用于登录。

### 5.2 登录入口（历史）

当前 GitLab 登录页只有「Keycloak 统一登录」一个第三方入口，点它走 `/users/auth/openid_connect` → Keycloak，密码仍在 OpenLDAP 校验。`Corp LDAP` 标签页已随 `ldap_enabled=false` 消失。

GitLab 19.6.1 中，LDAP 用户**不能**用登录页的 "Standard" 标签页（Devise 本地密码通道）——这条机制在 OIDC 下依然成立：用户记录仍带 `provider=ldapmain`，网页本地密码永远无效。

```ruby
# app/models/user.rb
def allow_password_authentication_for_web?
  return false if ldap_user? && !Gitlab::Auth::Ldap::Config.prevent_ldap_sign_in?
  ...
end
```

`ldap_user? == true` 时 `valid_password?` 恒为 false，所以对 LDAP 用户提交 `user[login]/user[password]` 一定返回 `Invalid login or password.`（HTTP 200，且不会建号）。

直连时代正确的入口是登录页的 **"Corp LDAP" 标签页**，它直接 POST 到 `/users/auth/ldapmain/callback`（**已停用，仅作机制说明**；现在等价的是先走 `/users/auth/openid_connect`，Keycloak 认证后再回 GitLab 建号）：

```bash
# 1) 取登录页，从 LDAP 表单内提取 authenticity_token
curl -s -c /tmp/cj http://192.168.200.12/users/sign_in -o /tmp/si.html
# 2) 提交
curl -s -b /tmp/cj -c /tmp/cj -X POST http://192.168.200.12/users/auth/ldapmain/callback \
  --data-urlencode "authenticity_token=<token>" \
  --data-urlencode "username=dev01" \
  --data-urlencode "password=${LDAP_USER_INIT_PASS}"
# 成功：302 → http://192.168.200.12/
```

两个易错点：token 必须是 **LDAP 表单里那一个**（页面有多个 token，取错会 302 回 `sign_in`）；`-L` 跟随会用 POST 请求 `/`，返回 404 是正常现象，别误判失败。

### 5.3 用户：首次登录即自动建号（API 预置是可选加速）

**（直连时代记录，OIDC 下同理）**：早前判断"GitLab 不会自动建号"是测错了入口——那时用的是 "Standard" 标签页。走 LDAP 入口首次登录，GitLab 会按 LDAP 条目自动创建用户（`Gitlab::Auth::Ldap::User#find_user` → `build_new_user`，`block_auto_created_users=false` 时不阻塞）；现在改由 `openid_connect` 首次登录触发同样的建号逻辑。

实测：只在 LDAP 里建 `tmp01`（GitLab 侧不存在），用 LDAP 标签页登录 → 302 到 `/dashboard/projects`，GitLab 自动生成 `tmp01 id=13 state=active provider=ldapmain extern_uid=uid=tmp01,ou=people,dc=corp,dc=local`。

因此**日常新增账号只需在 LDAP 做一次**，用户第一次登录 GitLab 时就自动出现，不需要管理员手工建号。

`POST /api/v4/users` 预置方式（带 `provider=ldapmain` + `extern_uid`=DN）仍然有用，适用两种场景：

- 需要**批量导入**、且不想等每个人首次登录（例如要提前统一赋权）
- 用户先要能被加进组，但还没登录过（未建号时 `POST /groups/:g/members` 会失败）

```bash
curl -X POST http://192.168.200.12/api/v4/users \
  -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  --data-urlencode "email=dev01@corp.local" \
  --data-urlencode "username=dev01" \
  --data-urlencode "name=陈开发" \
  --data-urlencode "password=${LDAP_USER_INIT_PASS}" \
  --data-urlencode "provider=ldapmain" \
  --data-urlencode "extern_uid=uid=dev01,ou=people,dc=corp,dc=local" \
  --data-urlencode "skip_confirmation=true"
```

`extern_uid` 必须与 LDAP 里的 DN 完全一致，登录时 `bind_as` 返回的 DN 才能匹配上身份。建号后本地密码无效（LDAP 用户不参与本地密码校验），认证一律回 LDAP。当时 10 个账号 id=3~12（现 12 个）。

### 5.4 组与项目权限（CE 无 LDAP 组同步）

GitLab CE 不支持 LDAP 组同步（Premium 功能），权限靠 API 手工落地：

```bash
# 组内成员
curl -X POST http://192.168.200.12/api/v4/groups/6/members \
  -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  --data-urlencode "user_id=6" --data-urlencode "access_level=30"

# 项目共享给组（组内成员自动继承）
curl -X POST http://192.168.200.12/api/v4/projects/2/share \
  -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  --data-urlencode "group_id=6" --data-urlencode "group_access=30"

# lead01 设为实例管理员
curl -X PUT http://192.168.200.12/api/v4/users/3 \
  -H "PRIVATE-TOKEN: ${GITLAB_PAT}" --data-urlencode "admin=true"
```

现状：

| GitLab 组 | id | 成员 |
|---|---|---|
| devops | 5 | ops01:40、ops02:40、lead01:40、root:50 |
| developers | 6 | dev01–dev05:30、root:50 |
| qa | 7 | qa01:20、qa02:20、root:50 |

项目 `root/podinfo`（id=2）共享：`devops:40`、`developers:30`、`qa:20`。`access_level`：`50=owner`、`40=maintainer`、`30=developer`、`20=reporter`。

### 5.5 为什么组权限不能全自动：CE 与专业版的边界

`https://gitlab.cn/docs/jh/administration/auth/ldap/ldap_synchronization/` 讲的是**极狐 GitLab（JH）专业版/旗舰版**的能力，其中：

- **用户同步**（把 LDAP 里所有人都拉进 GitLab，不必等首次登录）：EE/JH 的 `ldap_sync_*` 定时任务。
- **组同步**（`group_base` + `ldap_group_links` + `admin_group` 等，含 minimal access role）：EE/JH 专有。

本机是 **GitLab CE 19.6.1**（`Gitlab.ee? == false`、`Gitlab.jh? == false`），实测：

```
  ee/lib/gitlab/auth/ldap/            → 目录不存在（组同步代码全在 ee/ 下）
  gitlab.rb 模板 LDAP 组同步键         → 0 个（无 group_base/group_links/admin_group 注释位）
  lib/gitlab/auth/ldap/config.rb      → 仍能读 group_base 配置，但 CE 无消费方
```

所以在 CE 上能自动的只有两件事：**认证回 LDAP**（每次登录实时校验）、**首次登录自动建号**。不能自动的是**组成员与项目权限**，需要一次性 API 赋权（第 5.4 节的命令即为完整做法，早期一次性脚本已归档）。

三种处理路径对比：

| 方案 | 新人入职成本 | 说明 |
|---|---|---|
| 现状（CE + 脚本赋权） | 1 次 LDAP + 1 次脚本 | 新用户登录后由管理员跑一条赋权脚本；可包装成 `scripts\ldap\ldap-add-user.sh` |
| 升级到 JH 专业版 | 只在 LDAP 建号 | 组同步按 `group_base` 自动拉人、按组给权限，`minimal access` 受限角色也支持 |
| 自建同步脚本 + 定时任务 | 只在 LDAP 建号 | 定时比对 LDAP 组与 GitLab 组并补差，等价于自实现组同步；维护成本在脚本本身 |

> Harbor 侧不受此限制，它原生支持 LDAP 组继承，改 LDAP 组后用户重新登录即生效。

### 5.6 CE 自建组同步：脚本 + 定时器

既然 CE 没有 `ldap_group_sync`，就用 API 自己做一份等价实现，做到**只在 LDAP 加一次，10 分钟内 GitLab 自动补号并补组**。

**脚本** `scripts\ldap\ldap-gitlab-sync.sh` → 服务器 `/usr/local/bin/ldap-gitlab-sync.sh`

每次运行做的事：

1. 拉取 GitLab 全部用户，建立 `uid → id` 索引
2. 读 LDAP 的 `devops`/`developers`/`qa`/`platform-admins` 组成员（`member` 值先解 base64，再按 DN 查条目的 `uid` 属性）
3. 组内成员在 GitLab 不存在 → 调 `POST /api/v4/users` 建号（`provider=ldapmain` + `extern_uid`=真实 DN，名称取 LDAP `cn`，邮箱取 `mail`）
4. 组内缺人 → `POST /groups/:id/members` 补齐；已有但等级不对 → `PUT` 调级
5. 组内多了 LDAP 账号（已退出该组）→ `DELETE /groups/:id/members/:user_id` 清退；`root` 等非 LDAP 账号**永不涉及**
6. `platform-admins` 成员 → `PUT /users/:id` 设 `admin=true`（只升不降）

映射表在脚本头部，改权限等级只需改这里：

```bash
declare -A GMAP=([devops]="5:40" [developers]="6:30" [qa]="7:20")
# 组 cn → "GitLab 组 id:access_level"
```

**定时器**（systemd，比 cron 好排错，日志进 journal）：

```bash
# 只读模式先看一遍会做什么
/usr/local/bin/ldap-gitlab-sync.sh --dry-run

# 立即同步一次
/usr/local/bin/ldap-gitlab-sync.sh

# 定时器状态 / 下次执行 / 日志
systemctl list-timers ldap-gitlab-sync.timer
journalctl -u ldap-gitlab-sync.service -n 30 --no-pager
tail -20 /var/log/ldap-gitlab-sync.log
```

| 单元 | 内容 |
|---|---|
| `/etc/systemd/system/ldap-gitlab-sync.service` | `Type=oneshot`，`ExecStart=/usr/local/bin/ldap-gitlab-sync.sh`，`TimeoutStartSec=300` |
| `/etc/systemd/system/ldap-gitlab-sync.timer` | `OnBootSec=3min`、`OnUnitActiveSec=10min`、`AccuracySec=30s` |

常用开关（环境变量）：

```bash
REMOVE_STALE=0 /usr/local/bin/ldap-gitlab-sync.sh   # 只加不删，先观察一段时间再开启清退
GL=http://192.168.200.12 LDAP_HOST=... GL_TOKEN=... # 换环境/换 token
LDAP_USER_PW='<初始密码>'                            # 自动建号用的初始密码
```

**实测记录**（`scripts\ldap\188-regress.sh`，幂等回归连跑两次全零）：

```
A. 只在 LDAP 建 tmp03 并加入 developers → GitLab 侧「不存在」
B. 跑同步 → 建号成功 tmp03 → id=16；加组成功 tmp03 → 组6 (lvl=30)
C. developers 成员: root:50, dev01~dev05:30, tmp03:30
D. LDAP 里把 tmp03 移出 developers → 再跑同步 → 移除 tmp03 ← 组6
E. 清理后 developers 成员回到 root + dev01~dev05，无残留
```

幂等性：再跑一次输出 `建号 0，加组 0，移除 0，设管理员 0，错误 0`，不会重复调用 API。

**线上实证（2026-11-25 19:50）**：用 phpLDAPadmin 网页新建 `cn=遗留账号1`（uid `legacy1`，uidNumber 1000）并只加进 `platform-admins`，**没有做任何手工操作**，下一轮定时器自动产出 GitLab `id=22 / name=遗留账号1 / is_admin=true / extern_uid=cn=遗留账号1,ou=people,dc=corp,dc=local`。同时说明两个网页建号细节：接口按 `uid` 属性识人（DN 是 `cn=` 也照样匹配），且 `platform-admins` → 实例管理员的链路是通的。

**几个边界，已在脚本里处理**：

| 情况 | 行为 |
|---|---|
| 组里 member 指向已删除的 LDAP 条目（悬空 DN） | 先比对 `ou=people` 实际条目，悬空则跳过并记日志（本环境曾因界面里删 `lead02` 留下悬空引用） |
| 平台管理员在别的组里 | 不参与清退（`admins.txt` 白名单），避免把 lead01 从 devops 里删掉 |
| 用户在 LDAP 被整个删除 | 只影响组关系，**GitLab 账号不删**（CE 的 `ldap_sync` 才有删除动作）；离职需手工 `DELETE /users/:id?hard_delete=true` 或先 block |
| 同一人在多个组 | 各自独立赋权，GitLab 按最高权限生效；Harbor 同理 |
| 条目 DN 是 `cn=姓名,...`（网页模板生成） | 不按 DN 前缀判断，改为读条目 `uid` 属性；GitLab `extern_uid` 写真实 DN。实测建号 `id=20` 且 `extern_uid=cn=界面测试用户,...`，登录 302 正常 |
| 中文 DN / 中文 `cn` 在 LDIF 里变成 `dn:: `、`member:: `、`cn:: ` | 统一用 python3 解 base64 再解析（`dn_of`/`ld_members`/`user_meta`）；曾因只匹配 `member: ` 导致中文组员被漏读 |

**当前遗留**：GitLab 里有 `lead02`（id=15，admin，来自界面测试，LDAP 条目已删）和 `ghost`（id=14，删除用户后的占位账号）。不影响同步，需要时手工删除：

```bash
curl -X DELETE -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "http://192.168.200.12/api/v4/users/15?hard_delete=true"
```

### 5.7 ArgoCD 对接（Dex → Keycloak OIDC）

> **当前已改为 `type: oidc`**（connector id `argocd-dex`，secret `${ARGOCD_DEX_OIDC_SECRET}`，redirect `http://192.168.200.12:30080/api/dex/callback`），Dex 不再直接读 LDAP，而是让 Keycloak 完成联邦。下文的 `type: ldap` 配置是 11-25 历史版本，仅作回退/对照；生效配置见 `03-身份与账号/统一身份SSO-Keycloak.md` 7.4 与 `kubectl -n argocd get cm argocd-cm -o yaml`。

ArgoCD 没有自己的用户库，自带 Dex；**组 → 角色的映射不变**，只是组的来源从"LDAP groupOfNames"变成"Keycloak `groups` claim"：

```yaml
# 当前 argocd-cm（生效）
dex.config: |
  connectors:
  - type: oidc
    id: argocd-dex
    name: Keycloak
    config:
      issuer: http://192.168.200.12:30087/realms/corp
      clientID: argocd-dex
      clientSecret: $dex.argocd-dex.clientSecret
      insecureSkipVerify: true
      requestedScopes: ["openid", "profile", "email", "groups"]
```

**组 → 角色**（`argocd-rbac-cm`，实测生效）：

```yaml
data:
  policy.csv: |
    g, platform-admins, role:admin
    g, devops, role:admin
    g, developers, role:readonly
    g, qa, role:readonly
  policy.default: role:readonly
```

**生效**：`kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server`（ConfigMap 不热加载）。
脚本：`scripts\argocd\230-switch-oidc.sh`（直连 OIDC 版，已并入 Dex 桥接前的历史形态）、`237-switch-dex-bridge.sh` + `238-dex-enable-groups.sh`（当前生效的 Dex 桥接版），配置备份目录 `/root/argocd-sso-bak-<ts>/`。

**实测**：

| 账号 | 组 | 实际权限 |
|---|---|---|
| `dev01` | developers | 只读：列应用 200；`POST /api/v1/applications` → 403 permission denied |
| `lead01` | platform-admins | 管理员：建探针应用 200，删应用同样放行 |

- 登录页仍显示 **LOG IN VIA DEX**，点进去变成"Log in with Keycloak"，再输 `uid` + LDAP 密码。
- 登录成功后 `username` 形如 `dev01@corp.local`，`groups` 来自 Keycloak。
- 本地 `admin` 账号不受影响，仍是超级用户（可作应急登录）。

**注意**：

1. `clientSecret` 以 `$dex.argocd-dex.clientSecret` 引用 `argocd-secret`，不再把 LDAP bind 密码明文写进 `argocd-cm`。
2. Keycloak client `argocd-dex` 的回调必须是 `http://192.168.200.12:30080/api/dex/callback`（Dex 侧是 `/auth/callback` 由 Dex 自己处理），写错会 `Unregistered redirect_uri`。
3. RBAC 里写的是**组名**，不是 DN；Keycloak 侧同名 client 需开 group membership mapper 输出 `groups`。
4. 改组后用户需**重新登录**才刷新 `groups`（JWT 里带着，不实时查询）。
5. **条目必须有 `mail`**：Keycloak LDAP 联邦的 `email` 映射读 `mail`，缺了会在 Keycloak 侧报 `invalid email` 或用户导入后无邮箱。phpLDAPadmin 原版模板没有 Email 字段，本环境已补（见 5.7.1）。

**5.7.1 常见错误：`missing following required attribute(s): ["mail"]`**

现象：Dex 日志先 `username mapped to entry`（说明 uid/密码都对了），紧接着 `failed to login user`，`err` 里写缺 `mail`。原因是网页建号时模板里没有 Email 字段，条目只有 `inetOrgPerson + posixAccount` 的必填项。

修法（已有条目补一条属性即可，无需重启任何服务）：

```bash
ldapmodify -x -H ldap://127.0.0.1:389 -D 'cn=admin,dc=corp,dc=local' -w '${LDAP_ADMIN_PASS}' <<'EOF'
dn: cn=遗留账号1,ou=people,dc=corp,dc=local
changetype: modify
add: mail
mail: legacy1@corp.local
EOF
```

模板侧已永久修正：`/var/www/phpldapadmin/templates/creation/posixAccount.xml` 增加 `mail`（display 名 `Email`，`=autoFill(mail;%uid%@corp.local)` 自动按 uid 生成），模板文件同时留档在 `scripts\ldap\posixAccount.xml`，重装 phpLDAPadmin 后需重新 `podman cp` 覆盖一次（该文件在命名卷 `/var/www/phpldapadmin` 内，容器重启不丢）。

排查命令：`scripts\sonar-jfrog\1121-ldap-people.sh`（列出全部账号的 DN/uid/uidNumber/mail，标记缺失者）；建号模板已内置 `mail` 字段（`scripts\ldap\posixAccount.xml`，`=autoFill(mail;%uid%@corp.local)`）。


## 6. 日常运维

### 新增用户

> **逐步操作手册见 `docs/03-身份与账号/LDAP新增用户手册.md`**（网页 6 个输入框、入组、验证、十个常见坑）。

**自动化路径（推荐）**：只在 **phpLDAPadmin（http://192.168.200.12:8090）** 建条目 + 拖进对应组，10 分钟内定时同步会自动在 GitLab 建号并赋组权限，Harbor 侧用户重新登录即生效。

网页建号的三个既有事实（已实测，不用纠结）：

- 模板 `Generic: User Account` 的 `<rdn>` 是 `cn`，所以条目 DN 为 `cn=姓名,ou=people,dc=corp,dc=local`，**不是** `uid=xxx`；同步脚本改为读条目 `uid` 属性、并以真实 DN 写 GitLab `extern_uid`（实测 `extern_uid=cn=界面测试用户,...`，登录 302 正常）。
- 密码由模板 `<post>=php.PasswordEncrypt(...)</post>` 按 `pla_password_hash=md5` 落库为 `{MD5}`（base64 形式），已实测能 bind，可直接登录 GitLab/Harbor；要 `{SSHA}` 走下面的命令行路径或改密码流程。
- 模板 `gidNumber` 是 `posixGroup` 的 PickList，而本环境组都是 `groupOfNames`，故新增占位组 `cn=users,ou=groups`（`posixGroup` + `gidNumber: 10000`）供下拉选择，**不参与任何权限**。

**手工路径（需要立刻生效时）**：

1. 服务器上一条命令：`ldap-add-user.sh dev06 韩开发 developers [uidNumber]`（生成 `{SSHA}`、建 `uid=` 条目、入组、立即触发同步并打印 GitLab 建号结果；已实测）
2. 或者用 phpLDAPadmin 建条目并入组，然后立即跑 `/usr/local/bin/ldap-gitlab-sync.sh`（不等定时器）
3. Harbor 无需操作；GitLab 侧同步脚本已按"真实 DN"建号，无需再手工 `POST /api/v4/users`

### 新建组 / 新建 OU

**逐步操作（网页 + 命令行，含实测输出与八个坑）见 `docs/03-身份与账号/LDAP新增用户手册.md` 第 9 节。**

要点三条：

1. 权限组必须是 `groupOfNames`（GitLab 同步、Harbor 组继承、ArgoCD RBAC 都只认它）；`posixGroup`（`cn=users`）只是网页 GID 下拉的占位。
   - 原版 phpLDAPadmin 无 `groupOfNames` 模板，已补 **`Corp: Permission Group`**（`scripts\ldap\groupOfNames.xml`，`podman cp` 进 `/var/www/phpldapadmin/templates/creation/`，随命名卷持久）。
   - 命令行：`ldap-add-group.sh <组名cn> [说明] <首个成员uid或DN>`（`groupOfNames` 强制 ≥1 成员；组名限小写字母数字 `.-_`；成员按 `ou=people` 解析成真实 DN）。
2. 新建 OU：网页模板 `Generic: Organisational Unit`，或 `ldap-add-ou.sh <ou名> [说明] [父DN]`。
   新 OU 只当分区用：GitLab/Harbor 的 base 是 `dc=corp,dc=local`（能搜到），但 **Dex 的 `userSearch.baseDN` 写死 `ou=people`**，新 OU 里的人登不了 ArgoCD；Harbor 的组基也固定 `ou=groups`，权限仍只认那里的组。
3. **新组默认零权限**，要按需在三处登记：

| 系统 | 登记位置 | 不登记的后果 |
|---|---|---|
| GitLab | `ldap-gitlab-sync.sh` 顶部 `GMAP`（组名:GitLab组id:级别），需先建 GitLab 组拿 id | 该组被同步脚本静默忽略（实测：不报错、不建 GitLab 组） |
| Harbor | 项目 → 成员 → 添加组成员（组名精确，`group_type` 整数 1） | 组成员在该项目里没有任何角色 |
| ArgoCD | `argocd-rbac-cm` 的 `policy.csv` 加 `g, <组名>, role:readonly\|admin` + 重启 server | 该组落到 `policy.default=role:readonly` |
| Sonar | Administration → Security → Groups 里把 Keycloak 组授权为 admin/scan（或改 `cicd-gate` 权限） | 该组成员只能登录，不能执行分析/管理 |
| Jenkins | `jenkins.yaml` 的 `globalMatrix` 加组权限 | 该组只有 `Overall/Read`，不能构建 |
| Keycloak | realm `corp` → Users/Groups 由 LDAP 联邦自动同步（READ_ONLY，不可在 KC 里改人） | 组不会出现在各系统的 `groups` claim 里 |

组名是**三套系统共用的主键**（字符串精确匹配、大小写敏感），建好后不要改 `cn`——改 `cn` 等于换组，GitLab `extern_uid`/组映射、Harbor 组成员、ArgoCD policy 全部失配。

### 改密码

```bash
ldapmodify -x -H ldap://192.168.200.12:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' <<'EOF'
dn: uid=dev01,ou=people,dc=corp,dc=local
changetype: modify
replace: userPassword
userPassword: {SSHA}<新哈希>
EOF
```

Harbor、GitLab、Jenkins、Sonar、ArgoCD 都在登录时回 LDAP（或经 Keycloak 回 LDAP）校验，改完即生效，无需重启任何服务；但**已登录的 JWT/会话不会失效**，敏感场景（如离职）还需在对应系统里 block 用户。

### 复核命令

```powershell
cd C:\Users\morning\Desktop\cicd
# 目录侧（账号/组/memberOf）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1120-ldap-dump.sh --timeout 90
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1122-ldap-extra.sh --timeout 120
# Harbor 成员 + GitLab 用户（OIDC 后只作账号一致性核对）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1123-users-check.sh --timeout 250
```

## 7. 安全与已知限制

1. **389 明文**：当前未配 TLS（`LDAP_TLS=false`）。生产环境建议加 `LDAPS 636` 或 StartTLS；注意改完 Lead 的不只是 GitLab，Keycloak 的 LDAP 组件、Artifactory 的 `corp-ldap`、Harbor 都要同步改。
2. **单点**：LDAP 容器挂了，**所有系统的新登录全部失败**（Keycloak 是唯一入口，影响面比直连时代更大）；已登录会话按 token 有效期继续。`openldap.service` 已 enable，但建议加探活与告警。
3. **GitLab CE 无组同步**：靠 `ldap-gitlab-sync.sh` + `ldap-gitlab-sync.timer`（每 10 分钟）兜住，见 5.6；Harbor/Sonar 靠组继承与 OIDC claim，改组后用户重新登录即生效。
4. **memberof overlay 重复**：`cn=config` 里有重复的 `memberof/refint` 定义（`{0}`~`{3}`），功能正常但属遗留，清理需谨慎（备份在 `/root/openldap-config-bak-<ts>/`）。
5. **密码统一初始值**：12 个账号共用 `${LDAP_USER_INIT_PASS}`（含持有平台管理员权限的账号），交付后应按人分设，管理员账号单独强密码。
6. **非标准 DN 与越权组**：见 2.3——两个 `cn=` 形式账号（uidNumber 1000/1001）、一个 `cn=test,dc=corp,dc=local` 的越界组，其中一个账号同时是 `platform-admins` 成员。**建议尽快收敛**，否则该个人账号可经 Keycloak 拿到 GitLab/Harbor/Jenkins/Sonar/ArgoCD 的管理员权限。
7. **悬空 member**：`platform-admins`/`developers` 里的中文 DN 以 base64 形式存储（`member::`），脚本已按 base64 解码处理（见 5.6）；但人工 `ldapsearch` 时容易看漏。

## 8. 相关脚本

2026-11-26 精简目录后，`scripts\ldap\` 只保留**还会被复用**的脚本；一次性排错脚本已归档到 `_archive\scripts-full-backup-20261126.zip`。

| 脚本 | 用途 |
|---|---|
| `ldap-add-user.sh` | 日常建号（自动取号、入组、触发同步） |
| `groupOfNames.xml` / `posixAccount.xml` | phpLDAPadmin 建组/建号模板（含 `mail` 自动填充） |
| `ldap-add-group.sh` / `ldap-add-ou.sh` | 建权限组、建 OU（校验 RDN、重复拦截） |
| `ldap-gitlab-sync.sh` | LDAP→GitLab 组同步实现（服务器 `/usr/local/bin/` 同名文件 + systemd timer） |
| `120-probe-ldap.sh` / `121-ldap-install.sh` / `122-ldap-data.sh` | 探测 → 安装 OpenLDAP → 导入 OU/用户/组 |
| `170-phpldapadmin.sh` / `175-install-sync.sh` | 部署 phpLDAPadmin（8090）、装同步脚本与 timer |
| `188-regress.sh` / `192-final-state.sh` / `193-check-newbie.sh` | 幂等回归、终态核对、逐个条目对账 |
| `scripts\sonar-jfrog\1120~1122` | 全量导出账号/组/非标准条目（对账首选） |
| `scripts\sonar-jfrog\1123-users-check.sh` | GitLab 用户清单 + Harbor `apps` 成员核对 |

