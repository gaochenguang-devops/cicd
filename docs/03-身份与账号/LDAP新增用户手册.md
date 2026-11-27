# 新增 LDAP 用户 · 傻瓜手册

> 目标：**只在一个地方建人**（OpenLDAP），GitLab / Keycloak / Harbor / ArgoCD / Jenkins / Sonar / Artifactory 自动跟着生效。
> 环境：`192.168.200.12`，域名 `corp.local`。全流程 5 分钟。
>
> **当前现状（2026-11-26）**：登录入口统一为 **Keycloak**（GitLab 的 `Corp LDAP` 标签页已停用，Harbor/ArgoCD/Jenkins/Sonar 都点各自的「Keycloak / 统一登录」；Artifactory 是唯一 LDAP 直连，用同一个 `uid` + 密码直接登）。目录里现有 12 个账号（10 个标准 `uid=` + 2 个历史 `cn=` 条目，后者不要效仿，见第 10 节）。手册主体（建号 → 入组 → 同步 → 验证）不变。

---

## 0. 先记住这三步

```
① 在 phpLDAPadmin 建人（ou=people，DN 必须是 uid=…）   →   ② 把人塞进一个组（ou=groups）
                                                              ↓  10 分钟内自动
                                                        ③ GitLab 自动建号 + 赋组权限
                                                           Harbor / Sonar / Jenkins / ArgoCD 重新登录即生效
                                                           Artifactory 直连 LDAP，重新登录即生效
```

> 要新增**权限组**或**分区（OU）**？见第 9 节（网页模板 `Corp: Permission Group` / 命令 `ldap-add-group.sh`、`ldap-add-ou.sh`）。

**组决定权限**，不用单独给个人授权：

| 组（ou=groups） | 含义 | GitLab 组角色 | Harbor 项目角色 | ArgoCD | Sonar |
|---|---|---|---|---|---|
| `platform-admins` | 平台管理员 | 实例 **管理员**（Admin） | 系统管理员 | admin | admin |
| `devops` | 运维 | maintainer（40） | maintainer | admin | admin |
| `developers` | 开发 | developer（30） | developer | readonly | scan |
| `qa` | 测试 | reporter（20） | guest | readonly | scan |

---

## 1. 两条路，选一条

| 方式 | 适合 | 耗时 |
|---|---|---|
| **A. 网页点鼠标**（推荐，本手册重点） | 偶尔加人、给人演示 | 5 分钟 |
| **B. 服务器一条命令** | 批量加人、要精确控制 uidNumber | 30 秒 |

两条路的最终效果完全一样，都会触发同一个同步脚本。

---

## 2. 方式 A：网页建号（phpLDAPadmin）

### 2.1 打开并登录

浏览器访问 **http://192.168.200.12:8090**

| 登录框 | 填入 |
|---|---|
| Login DN | `cn=admin,dc=corp,dc=local` |
| Password | `${LDAP_ADMIN_PASS}` |

点 **Login**。左侧出现目录树：`dc=corp,dc=local` → 下面有 `ou=people`、`ou=groups`。

> 打不开？容器挂了：`systemctl restart phpldapadmin`（服务器上执行）。

### 2.2 定位到 ou=people

左侧树里 **点 `ou=people`**，右侧显示现有 12 个用户（10 个 `uid=` 标准账号 + 2 个 `cn=` 历史条目）。
确认右侧标题是 `ou=people`，不要停在 `dc=corp,dc=local`（否则人建到根上，同步脚本找不到）。

### 2.3 选创建模板

右侧上方有两个入口，点左边的 **`Create a new entry here`**（在 `ou=people` 这一层）。
弹出模板列表，选：

> **`Generic: User Account`**

（不要选 `Generic: Address Book Entry` —— 那个没有 posixAccount，不给 uidNumber，后面全乱。）

### 2.4 填表（只有 7 个框需要动）

| 界面字段 | 填什么 | 举例 | 注意 |
|---|---|---|---|
| **First name** | 名 | `三` | 只填名，不填姓 |
| **Last name** | 姓 | `张` | |
| **Common Name** | 姓名 | `示例姓名` | **默认会自动填成"名 姓"（如 `遗留账号1`），必须手动改成"姓名"顺序**，GitLab 显示名直接取它；重名时写 `示例姓名(工号)` |
| **User ID** | 登录名 | `legacy1` | **全小写、唯一**，GitLab 用户名就是它 |
| **Email** | 邮箱 | `legacy1@corp.local` | 填完 User ID 会自动带出 `uid@corp.local`。**这个字段不能空**，ArgoCD 登录会报 `missing required attribute(s): ["mail"]` |
| **Password** | 初始密码 | `${LDAP_USER_INIT_PASS}` | 明文填，系统自己加密 |
| **GID Number** | 下拉选 **`users`** | `users` | 下拉框里只有这一个选项（占位组，gid=10000），必须选，否则提交报错 |
| UID Number | 不用动 | 可能自动给 `1000` | 只读。实测模板取号会从 **1000** 起，不在 10010+ 号段；**不影响登录与权限**，要统一号段建完后在条目页把 `uidNumber` 改成 10020 起 |
| Home directory | 不用动 | `/home/users/dev06` | 自动生成 |
| Login shell | 下拉 **Bash** | `/bin/bash` | 默认就是 Bash |

### 2.5 点 Create，核对结果

点最下方 **Create**。成功后页面跳到新条目，标题类似：

```
cn=张三,ou=people,dc=corp,dc=local
```

**这里是 `cn=张三` 而不是 `uid=dev06` —— 这是正常的**，不必改。原因：phpLDAPadmin 这个模板规定用 `cn` 作条目 RDN；同步脚本已经按"真实 DN"识别身份（实测 GitLab 里 `extern_uid=cn=张三,ou=people,dc=corp,dc=local`，登录正常）。

页面上确认三件事：
- `uid: dev06` ✅
- `mail: dev06@corp.local` ✅（模板已加 Email 字段并自动带出；若为空，ArgoCD 登录会失败，补法见第 5 节 1d）
- `userPassword: {MD5}xxxx` ✅（页面自动加密成 `{MD5}`，能正常登录）

### 2.6 把人塞进组（关键一步，漏了就没权限）

1. 左侧点 **`ou=groups`**
2. 点目标组，例如 **`cn=developers`**
3. 右侧属性区找到 **`member`**，点它右边的 **`add`**（有的版本是 `Add new attribute` 图标）
4. 弹出框里 **勾选刚建的用户**（列表就是 `ou=people` 里的条目，按 `张三` 找），没有列表就在输入框粘贴完整 DN：
   `cn=张三,ou=people,dc=corp,dc=local`
5. 点 **Update / Save**

看到 `member` 里有两个人以上（如 root、dev01…、张三）就对了。

---

## 3. 让它生效

### 3.1 自动（什么都不做）

服务器上有定时器，**每 10 分钟**跑一次，最长等 10 分钟。

### 3.2 立刻生效（推荐，等不及时）

服务器上执行一条：

```bash
systemctl start ldap-gitlab-sync.service
```

> ArgoCD 不需要这一步：它登录时实时读 LDAP 组，新人只要在组里，点登录页 **LOG IN VIA DEX** 进去就按组给权限；改组后重新登录即刷新。

然后看结果：

```bash
tail -5 /var/log/ldap-gitlab-sync.log
```

正常输出形如：

```
组 developers (GitLab id=6 lvl=30)：LDAP 成员 dev01 dev02 dev03 dev04 dev05 dev06
  建号成功 dev06 → id=20
  加组成功 dev06 → 组6 (lvl=30)
===== 结束：建号 1，加组 1，移除 0，设管理员 0，错误 0 =====
```

---

## 4. 验证（4 条，全绿即成功）

```bash
# 1) LDAP 里有这个人
ldapsearch -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' \
  -b ou=people,dc=corp,dc=local -LLL "(uid=dev06)" uid uidNumber mail | grep -E 'uid|mail'

# 2) GitLab 里已自动建号（id 应为新号，extern_uid 是真实 DN）
curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "http://192.168.200.12/api/v4/users?username=dev06" | jq '.[]|{id,username,name,extern:[.identities[].extern_uid]}'

# 3) 已在 GitLab 对应组里
curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "http://192.168.200.12/api/v4/groups/6/members/all" | jq -r '[.[]|.username]|join(", ")'
```

4) **让本人登录一次**：GitLab `http://192.168.200.12` → 登录页点 **「Keycloak 统一登录」**（2026-11-26 起 GitLab 已改为走 Keycloak，`Corp LDAP` 标签页已停用）→ 输入 `dev06` / 初始密码 → 成功后能看到对应组的项目。
Harbor `https://harbor.corp.local` → 直接用户名密码登录 → 能看到 `apps`、`library` 项目（`qa` 组只读）。

---

## 5. 十个容易踩的坑（对号入座）

| # | 现象 | 原因 / 处理 |
|---|---|---|
| 1 | 条目 DN 是 `cn=张三,...` 不是 `uid=dev06,...` | **不建议**。同步脚本能读 `uid` 属性所以不会坏，但 12 个现网账号里那 2 个 `cn=` 条目已经造成 Keycloak/GitLab 侧 DN 与 `uid` 对不齐、`uidNumber` 落到 1000/1001 的混乱。新建号请用 `uid`（方式 B）或改模板 RDN |
| 1b | GitLab 里姓名显示成"遗留账号1"（名在前） | Common Name 用了自动填充的"名 姓"。**不要事后改 `cn`**——`cn` 形式的 DN 会跟着变，GitLab 存的 `extern_uid` 就对不上、登录直接失效。正确做法是删条目重建（先按 6.2 摘组），或在 GitLab 侧只改显示名 |
| 1c | UID Number 是 `1000/1001` 而不是 10020 | 模板取号从 1000 起，与标准号段 10010–10019 冲突。**新建号请显式填 10020 起的号**；已有的两个 1000/1001 条目建议改号或重建 |
| 1d | 登录报 `missing following required attribute(s): ["mail"]`（ArgoCD/Dex 时代）或 Keycloak 侧无邮箱 | 条目没 `mail`。模板已加 Email 字段，新条目会自动带出；老条目录补一条即可（命令见第 7 节下方"补 mail"），不用重启服务 |
| 2 | 重名建不进去（`Already exists`） | 同 OU 下 `cn=` 会撞名。改成 `张三(dev06)` |
| 3 | 提交报 `gidNumber` 必填 / 下拉是空的 | 下拉必须选 `users`；若空的说明占位组被删了，见第 6.3 节恢复 |
| 4 | 建完人在 GitLab 找不到 | 忘了加组，或没跑同步。先查 `tail /var/log/ldap-gitlab-sync.log`，再 `systemctl start ldap-gitlab-sync.service` |
| 5 | GitLab 登录提示 `Invalid login or password` | 先确认是点 **「Keycloak 统一登录」**（不是 Standard 标签页，也不是已停用的 Corp LDAP 标签） |
| 6 | 密码是 `{MD5}`，担心不安全 | `{MD5}` 能正常 bind（已实测）。要 `{SSHA}` 就用方式 B，或用第 6 节改密码流程 |
| 7 | 改完密码 GitLab 还认旧密码 | GitLab 每次登录都回 LDAP 校验，改完即生效；已登录的会话不会掉 |
| 8 | 把人从组里移出后 GitLab 还有权限 | 下一次同步会移出（`10 分钟`内）。`platform-admins` 成员受白名单保护，不会被清退 |
| 9 | 只删 LDAP 条目，组里留着 `member` 引用 | 会变成悬空 DN，同步脚本会跳过并记日志。正确做法见第 6.2 节，先删 member 再删条目 |
| 10 | Harbor 里看不到项目 | 组不对（Harbor 按 `memberOf` 继承），或用户没**重新登录**（Harbor 登录时算组） |

---

## 6. 后续维护

### 6.1 改密码（两种）

**网页**：phpLDAPadmin → `ou=people` → 点该用户 → 右侧 `userPassword` → `modify` → 填新密码 → 保存。同样存成 `{MD5}`，能登录。

**命令行**（存 `{SSHA}`，更强）：

```bash
NEW='NewPass@2026'
H='{SSHA}'$(python3 -c "import hashlib,base64,os,sys;p=sys.argv[1].encode();s=os.urandom(8);print(base64.b64encode(hashlib.sha1(p+s).digest()+s).decode())" "$NEW")
ldapmodify -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' <<EOF
dn: cn=张三,ou=people,dc=corp,dc=local
changetype: modify
replace: userPassword
userPassword: $H
EOF
```

> 注意 DN 用**真实 DN**（网页建的通常是 `cn=...`），不确定就先
> `ldapsearch -b ou=people,dc=corp,dc=local "(uid=dev06)" dn` 查一下。

**补 mail**（ArgoCD 登录报缺 `mail` 时；网页也能做：点条目 → `mail` → `modify` → 填 `dev06@corp.local`）：

```bash
ldapmodify -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' <<'EOF'
dn: cn=张三,ou=people,dc=corp,dc=local
changetype: modify
add: mail
mail: dev06@corp.local
EOF
```


### 6.2 离职 / 删号（三步，顺序不能反）

```bash
A="-x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w ${LDAP_ADMIN_PASS}"
DN="cn=张三,ou=people,dc=corp,dc=local"   # 换成真实 DN

# ① 先从所有组摘掉（否则留悬空 member）
for g in platform-admins devops developers qa; do
  ldapmodify $A <<EOF
dn: cn=$g,ou=groups,dc=corp,dc=local
changetype: modify
delete: member
member: $DN
EOF
done

# ② 删条目
ldapdelete $A "$DN"

# ③ 删 GitLab 账号（LDAP 删人不会自动删 GitLab 账号）
ID=$(curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
     "http://192.168.200.12/api/v4/users?username=dev06" | jq -r '.[0].id // empty')
[ -n "$ID" ] && curl -s -X DELETE -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "http://192.168.200.12/api/v4/users/$ID?hard_delete=true"
```

GitLab 账号若仍残留（软删变成 blocked 状态），用硬删：
`gitlab-rails runner "User.find_by_username('dev06')&.destroy!"`

Harbor 无需操作（它不存本地用户，认证走 LDAP，删条目后即登不上）。

### 6.3 占位组 `cn=users` 被误删了怎么恢复

```bash
ldapadd -x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w '${LDAP_ADMIN_PASS}' <<'EOF'
dn: cn=users,ou=groups,dc=corp,dc=local
objectClass: posixGroup
cn: users
gidNumber: 10000
description: gid placeholder for phpLDAPadmin account creation
EOF
```

它只是给网页的 GID 下拉提供一个选项，**不参与任何权限**（没有 member，同步脚本也不认它）。

---

## 7. 方式 B：服务器一条命令

脚本已装在服务器：`/usr/local/bin/ldap-add-user.sh`（本机源文件 `scripts\ldap\ldap-add-user.sh`）。

```bash
ldap-add-user.sh <uid> <姓名> <组cn> [uidNumber]

# 例：加一个开发，自动取号
ldap-add-user.sh dev06 韩开发 developers

# 指定号段
ldap-add-user.sh dev07 杨开发 developers 10021
```

它会做四件事并立即同步：生成 `{SSHA}` 密码 → 建 `uid=dev06,...` 条目 → 加入组 → 触发同步、打印 GitLab 建号结果。

输出示例：

```
[1/3] 密码哈希 {SSHA}Lmtz7OIk...
[2/3] 已建 uid=ui03（uidNumber=10020）
[3/3] 已加入组 developers
    [2026-11-25 19:39:12]   建号成功 ui03 → id=21
    [2026-11-25 19:39:12]   加组成功 ui03 → 组6 (lvl=30)
```

批量加 5 个人就写 5 行，或：

```bash
while read -r uid name grp; do ldap-add-user.sh "$uid" "$name" "$grp"; done <<'EOF'
dev06 韩开发 developers
dev07 杨开发 developers
qa03 冯测试 qa
ops03 陈运维 devops
EOF
```

---

## 9. 建组织（ou）与建组（group）

> 一句话：**OU 是"分区文件夹"，组才是"权限"**。加人不用建组织；要给人新权限才建组。
> 两者都能网页点出来，也都能一条命令搞定（下文都有实测输出）。

### 9.1 先看清目录长什么样

```
dc=corp,dc=local                  ← 域，已建好，不要动
├── ou=people                     ← 放人，已建好（ArgoCD 只认这里）
├── ou=groups                     ← 放权限组，已建好
│   ├── cn=platform-admins        ← 管理员
│   ├── cn=devops                 ← 运维
│   ├── cn=developers             ← 开发
│   └── cn=qa                     ← 测试
└── ou=xxx                        ← 需要分区时才建（如 ou=contractors）
```

### 9.2 建 OU（组织单元）· 网页 1 分钟

1. 左侧点 **父节点**——一般直接建在根下，就点 `dc=corp,dc=local`
2. 右侧偏上点 **`Create a new entry here`**
3. 模板列表里选：

> **`Generic: Organisational Unit`**

4. 只有两个框：

| 界面字段 | 填什么 | 举例 | 注意 |
|---|---|---|---|
| **ou** | 分区名 | `contractors` | **小写英文**，别用中文/大写 |
| Description | 中文说明 | `外协人员` | 可空 |

5. 点 **Create** → 左侧树里立刻多出 `ou=contractors`。

**建之前先想清楚**（这决定人放在哪）：

| 系统 | 搜索基（写死的） | 新 OU 里的人会怎样 |
|---|---|---|
| GitLab | `dc=corp,dc=local` | 能搜到、能登录 |
| Harbor | 用户 `dc=corp,dc=local`；组 `ou=groups,dc=corp,dc=local` | 能登录；但**权限仍只认 ou=groups 里的组** |
| ArgoCD(Dex) | `ou=people,dc=corp,dc=local` | **登录会失败**，要改 `dex.config` 的 `userSearch.baseDN` 才能用 |

所以正确的用法是：**新 OU 只当"分区/归档区"**，人要权限还是放进 `ou=groups` 的组里。

### 9.3 建组（权限组）· 网页 2 分钟

权限组必须是 **`groupOfNames`** —— GitLab 同步脚本、Harbor 组继承、ArgoCD RBAC 全都只认这个类型。
（`Generic: Posix Group` 建出来的是 `posixGroup`，那只是给网页 GID 下拉用的占位（`cn=users`），**不能当权限组**。）

原版 phpLDAPadmin 模板列表里没有 `groupOfNames`，已补了一个，名字叫：

> **`Corp: Permission Group`**

步骤：

1. 左侧点 **`ou=groups`**
2. 右侧 **`Create a new entry here`**
3. 模板选 **`Corp: Permission Group`**
4. 填三个框：

| 界面字段 | 填什么 | 举例 | 注意 |
|---|---|---|---|
| **Group name** | 组名 | `contractors-lead` | **小写英文**。这个字符串就是 GitLab / Harbor / ArgoCD 里认的组名，**建好不要再改**（改 cn = 换了个组，三处权限映射全失效） |
| 说明 | 中文备注 | `外协负责人` | 可空 |
| **Members** | 下拉选**第一个成员** | `dev01` | `groupOfNames` 强制至少一个成员，空着提交会报错 |

5. 点 **Create**。
6. 继续加人：在新组页面 → `member` → 点右边 **`add`** → 勾选人（或粘贴完整 DN）→ **Update / Save**。流程和第 2.6 节完全一样。

> Members 下拉如果没渲染出来（个别版本 PickList 不生效），直接走 9.4 的命令行建组，10 秒搞定、效果一样；建完仍可回网页继续加成员。

### 9.4 建 OU / 建组 · 命令行 10 秒

脚本已装在服务器（`/usr/local/bin/`，本机源文件 `scripts\ldap\ldap-add-ou.sh`、`scripts\ldap\ldap-add-group.sh`）：

```bash
# 建分区
ldap-add-ou.sh contractors "外协人员分区"

# 建权限组（第三个参数是首个成员：可写 uid，也可写完整 DN）
ldap-add-group.sh contractors-lead "外协负责人" dev01
ldap-add-group.sh contractors-lead "外协负责人" dev01     # 重复建 → 直接报错退出
```

- 组名自动校验：只允许 **小写字母 / 数字 / `.` `-` `_`**，大写、中文、带空格会被拦下。
- 不给成员会直接拒绝（`groupOfNames` 的 schema 要求），提示你去拉一个现有成员。
- 成员写 `uid` 时会自动按 `ou=people` 解析成**真实 DN**（中文姓名用户也能解析，实测 `cn=遗留账号1,...` 正常）。

实测输出（真实执行过）：

```
[1/2] 建 ou=contractors,dc=corp,dc=local
      ou: contractors
      description: 外协人员分区

[1/2] 建组 cn=contractors-lead,ou=groups,dc=corp,dc=local（成员：uid=dev01,ou=people,dc=corp,dc=local）
      cn: contractors-lead
      member: uid=dev01,ou=people,dc=corp,dc=local
```

### 9.5 关键：新建的组默认**没有任何权限**

LDAP 里建完组，三套系统只是"知道有这个组"，一处权限都没给。按需登记：

**① GitLab（CE 不会自己建组，必须登记映射）**

```bash
# 1) 先建 GitLab 组，拿 id（网页建也行：左侧 Groups → New group）
curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X POST \
  "http://192.168.200.12/api/v4/groups" \
  -d "name=contractors-lead&path=contractors-lead" | jq '{id,name,path}'

# 2) 编辑同步脚本顶部的映射表（组名:GitLab组id:角色级别）
vi /usr/local/bin/ldap-gitlab-sync.sh
#    GMAP=([devops]="5:40" [developers]="6:30" [qa]="7:20" [contractors-lead]="8:30")

# 3) 立刻同步一次
systemctl start ldap-gitlab-sync.service
```

级别：`20` reporter / `30` developer / `40` maintainer / `50` owner。
**不登记会怎样**：同步脚本只处理 GMAP 里列出的组，新组被安静忽略（不会报错、也不会建图 GitLab 组），实测如此。

**② Harbor（按项目授权，组名照填）**

网页：目标项目 → `成员` → `添加成员` → 类型选 **用户组** → 组名填 `contractors-lead` → 选角色 → 确定。

命令行（以 `apps` 项目、guest=3 为例）：

```bash
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' -X POST -H 'Content-Type: application/json' \
  http://127.0.0.1:30090/api/v2.0/projects/apps/members \
  -d '{"role_id":3,"member_group":{"group_name":"contractors-lead","group_type":1}}'
```

role_id：`1` projectAdmin / `2` developer / `3` guest / `4` maintainer；`group_type` 必须是**整数 1**（1=LDAP），写成字符串会 422。

**③ ArgoCD（RBAC 加一行）**

```bash
kubectl -n argocd edit cm argocd-rbac-cm
# 在 policy.csv 末尾加：
#   g, contractors-lead, role:readonly     ← 要管理员就 role:admin
kubectl -n argocd rollout restart deploy/argocd-server
```

### 9.6 验证（4 条，全绿即成功）

```bash
A="-x -H ldap://127.0.0.1:389 -D cn=admin,dc=corp,dc=local -w ${LDAP_ADMIN_PASS}"

# 1) 组本身建对了（cn + member 都在）
ldapsearch $A -LLL -b 'ou=groups,dc=corp,dc=local' '(cn=contractors-lead)' cn description member

# 2) Harbor 能解析这个组（只读查询，实测返回 ldap_group_dn）
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' -G --data-urlencode 'groupname=contractors-lead' \
  http://127.0.0.1:30090/api/v2.0/ldap/groups/search

# 3) memberOf 已算出（Harbor 的组继承全靠它，overlay 会自动维护）
ldapsearch $A -LLL -b 'uid=dev01,ou=people,dc=corp,dc=local' memberOf

# 4) GitLab 侧是否跟上
tail -5 /var/log/ldap-gitlab-sync.log
```

### 9.7 建组织/建组的坑（对号入座）

| # | 现象 | 原因 / 处理 |
|---|---|---|
| 1 | 建组报 `object class 'groupOfNames' requires attribute 'member'` | `groupOfNames` 必须至少一个成员。先选一个人建，建完再加 |
| 2 | 模板列表里没有 `Corp: Permission Group` | 模板文件没拷进容器（重装 phpLDAPadmin 会丢）：`podman cp /root/groupOfNames.xml phpldapadmin:/var/www/phpldapadmin/templates/creation/groupOfNames.xml` |
| 3 | 用 `Generic: Posix Group` 建的组，三套系统都不认 | 那是 `posixGroup`；权限组只能 `groupOfNames` |
| 4 | 组名写成 `Contractors-Lead` 或中文 | 三套系统按字符串精确匹配，大小写敏感。脚本已拦大写；网页建的会被存进去但 Harbor 组名大小写要对上才认得 |
| 5 | 新组里的人 GitLab 里没动静 | GMAP 没登记。同步脚本只跑已知组，其他组静默忽略（不报错） |
| 6 | 新建 OU 后，里面的人登 ArgoCD 失败 | Dex 的 `userSearch.baseDN` 写死 `ou=people`。要支持得改 `argocd-cm` 的 `dex.config` 并重启 dex |
| 7 | 想改组名 | **别改 `cn`**。改了就等于换了组：GitLab `extern_uid`/组映射、Harbor 组成员、ArgoCD policy 全部失配。正确做法是建新组、迁人、删旧组 |
| 8 | 删组后 GitLab 那边还有组 | 删 LDAP 组只影响 LDAP；GitLab 组要手工删，并把 GMAP 里那行摘掉 |

---

## 10. 一页速查卡

```
网页：http://192.168.200.12:8090     admin: cn=admin,dc=corp,dc=local / ${LDAP_ADMIN_PASS}
建人（推荐命令）：/usr/local/bin/ldap-add-user.sh dev06 韩开发 developers
建人（网页）：ou=people → Create a new entry here → Generic: User Account
填：First name / Last name / Common Name(姓名) / User ID(小写) / Email / Password / GID=users
   ⚠️ RDN 必须是 uid，UID Number 用 10020 起，别沿用模板默认的 cn= 与 1000
入组：ou=groups → 点组 → member → add → 勾选人 → Save
建分区：点父节点 → Create a new entry here → Generic: Organisational Unit（ou 小写英文）
建组：ou=groups → Create a new entry here → Corp: Permission Group（组名小写 + 选首个成员）
生效：systemctl start ldap-gitlab-sync.service（或等 10 分钟）
新组赋权：GitLab 改 GMAP / Harbor 项目加组成员 / ArgoCD policy.csv / Sonar 组授权 / Jenkins globalMatrix
验证：tail -5 /var/log/ldap-gitlab-sync.log  → 应见「建号成功 <uid>」
登录：GitLab/Harbor/ArgoCD/Jenkins/Sonar 点各自「Keycloak / 统一登录」（GitLab 已无 Corp LDAP 标签页）；
      Artifactory 直接输 uid + 密码（唯一 LDAP 直连）
命令：ldap-add-user.sh dev06 韩开发 developers
      ldap-add-group.sh contractors-lead "外协负责人" dev01
      ldap-add-ou.sh contractors "外协人员分区"
```

---

## 11. 现网遗留（2026-11-26 实测，待清理）

目录里目前有 12 个账号 = 10 个标准 `uid=` + 2 个历史 `cn=` 条目：

| 条目 | 问题 | 建议 |
|---|---|---|
| `cn=遗留账号1,ou=people`（uid `legacy1`，uidNumber 1000） | 同时属于 `platform-admins`、`developers` 和 `ou=groups` 之外的 `cn=test` 组；即一个个人账号拥有平台管理员权限 | 先从 `platform-admins` 摘除，再确认是否保留账号 |
| `cn=legacy2,ou=people`（uid `legacy2`，uidNumber 1001） | DN 含空格，`mail` 是外部邮箱 | 重建为 `uid=legacy2,ou=people`，或删除 |
| `cn=test,dc=corp,dc=local` | `groupOfNames` 建在 Base 下、不在 `ou=groups`，各系统权限模型都不认它 | 删除或迁入 `ou=groups` 并登记权限 |

清理后 Keycloak 侧（READ_ONLY 联邦）会在下次同步自动消失，无需手工处理；GitLab 已建的账号不会自动删，需要 `DELETE /api/v4/users/<id>?hard_delete=true`。

相关：`docs/03-身份与账号/OpenLDAP目录.md`（架构、参数、权限矩阵、同步脚本细节）、`scripts\ldap\ldap-gitlab-sync.sh`（同步实现）、`scripts\sonar-jfrog\1120~1122`（现状导出脚本）。

