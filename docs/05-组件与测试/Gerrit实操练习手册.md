# Gerrit 实操练习手册（sandbox/lab）

> 这套环境是**给你随便练的沙箱**：项目 `sandbox/lab` 里的东西改坏了、推乱了、乱投 -2 都不影响其它系统，实在弄脏了还有一条命令重置回初始状态（见 8.5）。
>
> 全部命令都在本机 Windows PowerShell 里敲（Git for Windows 自带 `git` / `ssh` / `curl.exe`），服务器侧的操作另标注。**照第 3~5 章顺序走，大约 20 分钟能把「推送评审 → 打分合入 → 冲突处理」完整练一遍。**

---

## 1. 开箱信息

| 项 | 值 |
| --- | --- |
| Web 界面 | `http://192.168.200.12:8081` |
| SSH（git push / gerrit 命令） | `ssh://dev01@192.168.200.12:29418`，端口 `29418` |
| 匿名只读 clone（不登录，只能拉不能推） | `http://192.168.200.12:8081/sandbox/lab` |
| 练习项目 | `sandbox/lab`（Gerrit 项目名，clone 路径 `/sandbox/lab`） |
| 认证方式 | LDAP 表单登录，**第一次登录自动建号**（账号来自 `ou=people,dc=corp,dc=local`） |
| 服务形态 | podman 容器 `gerrit`（`--restart=always`），站点目录 `/data/gerrit` |

练习账号（口令都是 LDAP 用户初始口令，真实值在根目录 `.env` 的 `LDAP_USER_INIT_PASS`，文档里统一写 `${LDAP_USER_INIT_PASS}`）：

| 账号 | 姓名 | 在这套练习里的角色 |
| --- | --- | --- |
| `dev01` | 陈开发 | 作者：改代码、push 评审 |
| `lead01` | 李平台 | 评审人：打分 `+2`、点 Submit 合入 |
| `qa01` | 钱测试 | 旁观者：验证「没打分的人看得到但改不了」 |

项目 ACL（已预置，`Registered Users` 都能用，不需要管理员）：

| 权限 | 授予 | 效果 |
| --- | --- | --- |
| `read` | Anonymous Users | 不登录也能 clone / 看代码 |
| `push` / `pushMerge`（`refs/for/*`） | Registered Users | 任何登录用户都能推评审 |
| `label-Code-Review` `-2..+2` | Registered Users | 任何登录用户都能打 -2 ~ +2 |
| `submit` | Registered Users | 任何登录用户都能合入（练习环境故意放开，生产不会这么配） |
| `requireChangeId` | 项目级 | 提交必须带 `Change-Id`（缺了推不上去） |

> 生产环境的正确配法通常是「作者只能 `-1..+1`、评审组才能 `+2`、只有 Maintainer 能 `submit`」。这里为了单人也能练全流程，把 `+2` 和 `submit` 放给了所有登录用户。

---

## 2. 开局三件事（5 分钟）

### 2.1 先确认路通了

```powershell
# Web 端口（期望 200）
curl.exe -s -o NUL -w "web:%{http_code}`n" http://192.168.200.12:8081/

# SSH 端口（期望 True）
Test-NetConnection 192.168.200.12 -Port 29418 -InformationLevel Quiet

# 本机工具（git 2.4x 以上即可，curl.exe 是 Windows 自带的）
git --version
```

任一项不通，先看第 7 章排障表，不要往下走。

### 2.2 浏览器登录

打开 `http://192.168.200.12:8081`，右上角 **Sign In**，用户名填 `dev01`、口令填 `.env` 里的 `LDAP_USER_INIT_PASS`。

第一次登录 Gerrit 会用 LDAP 里的 `cn` / `mail` 自动建号，登录后右上角能看到「陈开发」。用 `lead01` 再登一次（建议开一个浏览器隐私窗口，两个账号互不打架），确认也是自动建号成功。

### 2.3 SSH key（只做一次）

本机已经有一把**已绑定 `dev01`** 的 key：`C:\Users\morning\.ssh\gerrit-lab`（无口令）。想直接用自己的 key 就走下面两步：

```powershell
# 1) 生成（交互式，直接回车两次 = 不设口令；不要用 -N '""'，在 PowerShell 里会被当成口令字符，之后 ssh 会卡在输口令）
ssh-keygen -t ed25519 -C "gerrit-lab@$env:USERNAME"

# 2) 复制公钥内容，粘贴到 Gerrit：右上角头像 → Settings → SSH Keys → New SSH Key
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

验证（下面这条能回 `gerrit version 3.9.11` 就对了）：

```powershell
ssh -i C:/Users/morning/.ssh/gerrit-lab -p 29418 -o StrictHostKeyChecking=accept-new dev01@192.168.200.12 gerrit version
```

用自己 key 的话把 `-i` 后的路径换掉即可。

---

## 3. 练习一：把一次改动推进评审（核心动作）

### 3.1 clone + 装 commit-msg 钩子

```powershell
cd $env:USERPROFILE\Desktop
git clone ssh://dev01@192.168.200.12:29418/sandbox/lab lab
cd lab

# 钩子负责自动生成 Change-Id，没有它 push 一定失败
curl.exe -s -o .git/hooks/commit-msg http://192.168.200.12:8081/tools/hooks/commit-msg

git config user.name  dev01
git config user.email dev01@corp.local
```

> 为什么不用 `scp`：`scp -P 29418 dev01@host:hooks/commit-msg .` 在 3.9 上会直接 `scp: Connection closed`（Gerrit 的 scp 通道不可用），`curl` 走 HTTP 取钩子是实测唯一稳的办法。

### 3.2 改一行，提交，推到 `refs/for/master`

`refs/for/master` 是 Gerrit 的「评审队列」：推到它不会直接进 `master`，而是生成一条 change 等评审。

```powershell
# 在 README.md 的「练习区」表格末尾加一行
"| 2026-11-27 | dev01 | 第一次练习 |" | Out-File -Append -Encoding utf8 README.md

git add README.md
git commit -m "docs: 练习区加一行（第一次）"
git log -1 --pretty=%B      # 确认 footer 里有 Change-Id: I....

git push origin HEAD:refs/for/master
```

成功的输出长这样（重点是 `SUCCESS` 和你自己的 change 链接）：

```
remote: SUCCESS
remote:   http://192.168.200.12:8081/c/sandbox/lab/+/12 docs: 练习区加一行（第一次）[NEW]
 * [new reference]   HEAD -> refs/for/master
```

此时：

- `master` **没有变化**（`git ls-remote origin refs/heads/master` 还是 `49e5bf9`）；
- 浏览器打开那条 `/c/sandbox/lab/+/12`，能看到 diff、`Change-Id`、`Status: NEW`、`Code-Review: 0`；
- 右上角 **Your → Changes** 里能看到自己所有未合入的 change。

### 3.3 补丁集是怎么来的（先记住这句）

同一个 `Change-Id` 再推一次，Gerrit 不会新建 change，而是给旧 change 追加一个 **patch set（补丁集）**，编号 +1。所以「改错了怎么办」的答案永远是：

```powershell
git commit --amend          # 保持 Change-Id 不变，只改内容/说明
git push origin HEAD:refs/for/master
```

而不是删 change 重来。

---

## 4. 练习二：打分、评论、合入

### 4.1 在 Web 上做（推荐先这样练）

用 `lead01` 登录（另一个浏览器窗口），打开 `http://192.168.200.12:8081/c/sandbox/lab/+/12`：

1. 看 diff：左侧旧、右侧新，行号可点；
2. 鼠标点到某一行左侧空白 → **双击行号** 可直接写行内评论（Reply 里保存为 draft，最后点 **Reply** 一起发）；
3. 右上角 **Reply** 面板里：
   - `Code-Review` 选 `+2`（我这版认可）或 `-2`（这版不能合）；
   - 写一句评论，点 **Send**；
4. 分数到位、且没有 `-2` 时，右上角出现 **Submit** 按钮，点它 → change 变 `Merged`，代码进 `master`；
5. 回作者窗口：`git pull` 能看到自己那行已经在本地了。

> 练习「打回」：在同一个 change 上选 `-2` + 说明原因，此时 Submit 会被禁用（`MaxWithBlock` 语义：有 -2 一律不许合）；作者 amend 修好后，你改成 `+2` 才能合。这是 Gerrit 和 GitHub PR 最大的行为差异之一。

### 4.2 用命令行做（评审人也常常懒得开网页）

```powershell
# 打分 + 合入，一条命令
ssh -i C:/Users/morning/.ssh/gerrit-lab -p 29418 dev01@192.168.200.12 gerrit review 12,1 --code-review +2 --submit

# 只查状态
ssh -i C:/Users/morning/.ssh/gerrit-lab -p 29418 dev01@192.168.200.12 gerrit query --format=JSON project:sandbox/lab status:open
```

`12,1` = `change 号,补丁集号`；补丁集写错会报 `"12" is not a valid patch set` 之类，直接看 Web 页面上的 `Patch Set N` 即可。

注意：`dev01` 给自己打分在练习环境里是允许的（ACL 放开了）；真实环境应该换 `lead01` 的 key 来打分，否则「自己写自己合」等于没有评审。

---

## 5. 练习三：冲突处理（最值得练的一段）

思路：**两个人从同一个基线改同一行**，先合一个，第二个必然冲突；冲突只能在本地 rebase 解决，再推成新的 patch set。

练习文件是仓库里的 `conflict-demo.txt`，里面只有一行有效内容：

```
shared_value = 1
```

### 5.1 准备两个工作副本（模拟两个人）

```powershell
cd $env:USERPROFILE\Desktop
git clone ssh://dev01@192.168.200.12:29418/sandbox/lab lab-a
git clone ssh://dev01@192.168.200.12:29418/sandbox/lab lab-b
foreach ($d in "lab-a","lab-b") {
  Push-Location $d
  curl.exe -s -o .git/hooks/commit-msg http://192.168.200.12:8081/tools/hooks/commit-msg
  git config user.name dev01; git config user.email dev01@corp.local
  Pop-Location
}
```

### 5.2 两个改动都推到评审（此时都不冲突）

```powershell
# A：把 1 改成 100
cd lab-a
(Get-Content conflict-demo.txt -Raw) -replace 'shared_value = 1','shared_value = 100' | Set-Content conflict-demo.txt -Encoding utf8
git commit -am "feat: shared_value 调整为 100"
git push origin HEAD:refs/for/master      # 记下 change 号，假设是 21

# B：把 1 改成 200（基线还是老 master，所以 push 也会成功）
cd ..\lab-b
(Get-Content conflict-demo.txt -Raw) -replace 'shared_value = 1','shared_value = 200' | Set-Content conflict-demo.txt -Encoding utf8
git commit -am "feat: shared_value 调整为 200"
git push origin HEAD:refs/for/master      # 记下 change 号，假设是 22
```

> 两条 change 都能推上去，是因为它们的父提交都还是当时的 `master` 头。Gerrit 只在**合入时**才真正检查能不能合并——这也是它和「先到先得」的 GitHub 合并队列的区别。

### 5.3 先合 A，再让 B 撞上冲突

用 `lead01` 在 Web 上给 `21` 打 `+2` 并 Submit（或命令行 `gerrit review 21,1 --code-review +2 --submit`）。此时 `master` 里是 `shared_value = 100`。

回到 B 的副本：

```powershell
cd ..\lab-b
git fetch origin
git rebase origin/master
```

预期报错（这就是要练的东西）：

```
CONFLICT (content): Merge conflict in conflict-demo.txt
error: could not apply xxxxxxx... feat: shared_value 调整为 200
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
```

`git status` 会显示 `both modified: conflict-demo.txt`，打开文件能看到冲突标记：

```
<<<<<<< HEAD
shared_value = 100
=======
shared_value = 200
>>>>>>> xxxxxxx (feat: shared_value 调整为 200)
```

### 5.4 解冲突 → 再推（变成 patch set 2）

```powershell
# 手工编辑 conflict-demo.txt，把整段替换成最终值（这里取 300，表示两边意图都吸收）
"shared_value = 300" | Set-Content conflict-demo.txt -Encoding utf8

git add conflict-demo.txt
git rebase --continue          # 若弹出编辑器写提交信息，直接保存退出即可（Change-Id 会保留）
git log -1 --pretty=%B         # 确认 Change-Id 还是原来那个

git push origin HEAD:refs/for/master
```

输出里 change 号不变、补丁集变 2：

```
remote: SUCCESS
remote:   http://192.168.200.12:8081/c/sandbox/lab/+/22 feat: shared_value 调整为 200 [NEW]
```

（Web 上该 change 的 `Patch Set 2` 会显示 `Rebase onto master`、旧补丁集上 `lead01` 的 `+2` 会失效，需要重新打分——这也是要练的点：**内容变了，分数要重打**。）

### 5.5 合入并验证

```powershell
# 评审人重新 +2 并合入 patch set 2
ssh -i C:/Users/morning/.ssh/gerrit-lab -p 29418 dev01@192.168.200.12 gerrit review 22,2 --code-review +2 --submit

# 作者侧收尾
git checkout master
git pull
Get-Content conflict-demo.txt   # 期望 shared_value = 300
git log --oneline -3            # 两条 change 的提交都在
```

### 5.6 冲突的三种收场方式（知道就行）

| 情况 | 做法 |
| --- | --- |
| 我的改动不该要了 | `git rebase --abort`，然后 Web 上 **Abandon** 这条 change |
| 对方改动该覆盖我的 | 解冲突时保留对方内容，`git add` + `rebase --continue` + 重推（本质是「我的补丁集改成空操作」） |
| 想重来一次 | `git rebase --abort` → 基于新 `master` 重新 `git checkout -b` 改一遍（Change-Id 会变，等于新 change） |

---

## 6. 练完可以再试试这些（可选）

| 练习 | 做法 | 观察点 |
| --- | --- | --- |
| 缺 Change-Id | `git commit --no-verify` 或删掉 footer 里的 `Change-Id` 再 push | 报 `missing Change-Id` / `no new changes`，钩子必须装 |
| 忘记装钩子 | 同上 | 同上，`git commit --amend` 后重推即可补上 |
| 一次推多条 | 基于 `master` 连做 3 个提交，`git push origin HEAD:refs/for/master` | Gerrit 生成 3 条 change，且互相是「依赖链」（后一条的 Relation chain 指向前一条） |
| 同一 change 追加补丁 | `git commit --amend` 后重推 | change 号不变、`Patch Set 2`，旧分数失效 |
| 弃用 change | Web 上 **Abandon**，或 `ssh ... gerrit review 21,1 --abandon` | 状态变 `Abandoned`，不再占评审队列 |
| 只看不推 | 用 `qa01` 登录，clone 后直接 `git push` | 因为 ACL 放开了，这里也会成功（生产会拒绝，注意差别） |

---

## 7. 排障速查表

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `Permission denied (publickey)`，且 `ssh -vvv` 卡在 `sign_and_send_pubkey` | key 带口令，ssh 在等输入（本工具/脚本环境没有 TTY 就表现为卡死） | 重新生成不带口令的 key：`ssh-keygen -t ed25519`，两处提示都直接回车；或 `ssh-keygen -p -f <key>` 清空口令 |
| `scp: Connection closed` | Gerrit 3.9 的 scp 通道不可用 | 用 `curl.exe -o .git/hooks/commit-msg http://192.168.200.12:8081/tools/hooks/commit-msg` |
| `missing Change-Id in commit message footer` | 钩子没装 / 提交早于钩子 | 装钩子后 `git commit --amend --no-edit`，再推 |
| `no new changes` | 推的提交远端已经有了（常见于「先推过一次、后来又没改动」） | 确认 `git log` 里有新提交；需要更新就 `--amend` 后重推 |
| `no common ancestry` | 推的是**重写过的初始提交**（比如 clone 下来直接 `git commit --amend` 改第一个提交） | 别改历史根提交；基于 `origin/master` 做**新提交** |
| `Applying label "Code-Review": 2 is restricted` | 项目 ACL 没生效（本次踩过：`refs/meta/config` 里缺 `groups` 文件，导致组名解析不到，ACL 被静默丢弃） | 见 8.3；把 `groups` 文件补进 `refs/meta/config` 后重启 |
| `submit not permitted` | 同上，`submit` 规则没生效 | 同上 |
| `"21" no such change` / `not a valid patch set` | change 号或补丁集号写错 | 以 Web 页面 `/c/.../+/NN` 和 `Patch Set N` 为准 |
| Web 登录报 `No such user` | 账号不在 LDAP（这套环境只有 `dev01~dev05`、`lead01`、`ops01/02`、`qa01/02`） | 用第 1 章表里的账号 |
| change 列表里还看得到某条 change，点进去却 `Not found` / 404 | 项目 `refs` 已删、changes 索引未清（重置后常见） | `podman stop gerrit` → `rm -rf /data/gerrit/index/changes_*` → `podman start gerrit`（8.5 的重置脚本已包含这一步） |
| 端口 8081 打不开 | 容器没起 / 被别的服务占了 | 服务器上 `podman ps --filter name=gerrit`、`podman logs --tail 50 gerrit` |

---

## 8. 环境事实与运维（服务器侧）

以下命令在服务器 `192.168.200.12` 上以 `root` 执行（本仓库统一用 `python scripts\tools\ssh_exec.py "..."` 远程跑）。

### 8.1 进程与端口

```bash
podman ps --filter name=gerrit                 # 容器 gerrit，端口 8081:8080 / 29418:29418
podman logs --tail 50 gerrit                  # 启动日志，正常结尾是 "Gerrit Code Review 3.9.11 ready"
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/    # 期望 200
```

容器启动命令（重建时照抄）：

```bash
podman run -d --name gerrit --restart=always --network gerrit-net \
  -p 8081:8080 -p 29418:29418 \
  -v /data/gerrit:/var/gerrit \
  docker.m.daocloud.io/library/eclipse-temurin:21-jre \
  java -jar /var/gerrit/bin/gerrit.war daemon -d /var/gerrit --console-log
```

> `8080` 已被宿主别的服务占用，所以对外映射到 `8081`；防火墙 `firewalld` 在本机是关的，端口直接可达。

### 8.2 站点目录

| 路径 | 内容 |
| --- | --- |
| `/data/gerrit/etc/gerrit.config` | 主配置（`auth.type=LDAP`、`ldap.*`、`canonicalWebUrl`、`sshd.listenAddress`） |
| `/data/gerrit/etc/secure.config` | `ldap.password`（LDAP 管理员口令，**不入库、不进文档**） |
| `/data/gerrit/bin/gerrit.war` | 3.9.11 的 war 包（84MB）；`/root/gerrit-keep/gerrit.war` 是备份 |
| `/data/gerrit/git/sandbox/lab.git` | 练习项目；ACL 在它的 `refs/meta/config`（`project.config` + `groups`） |
| `/data/gerrit/logs/` | `error_log` / `sshd_log` / `httpd_log`，SSH 登录记录在 `sshd_log` |
| `/data/gerrit/seed/lab.bundle` | 干净基线（`master` 初始提交 + `refs/meta/config`），重置用 |

### 8.3 坑：项目 ACL 必须有 `groups` 文件

Gerrit 的项目级 `project.config` 里写 `group Registered Users` 这类组名时，**必须在同一个 `refs/meta/config` 提交里带上 `groups` 文件**（组名 → 组 UUID 的映射）。缺了它不会报错，只会静默按 `-1..+1` / 无 `submit` 处理，于是：

- 普通用户打 `+2` 报 `Applying label "Code-Review": 2 is restricted`；
- 普通用户 Submit 报 `submit not permitted`。

修法（本次已落地在 `sandbox/lab`）：

```bash
# 把 All-Projects 的 groups 复制进项目 meta/config，再推 refs/meta/config
tmp=$(mktemp -d); cd $tmp; git init -q p; cd p
git fetch -q /data/gerrit/git/sandbox/lab.git refs/meta/config
git checkout -q FETCH_HEAD
git -C /data/gerrit/git/All-Projects.git show refs/meta/config:groups > groups
git add groups && git -c user.email=x@y -c user.name=x commit -qm "meta: add groups"
git push -q /data/gerrit/git/sandbox/lab.git HEAD:refs/meta/config
podman restart gerrit
```

另外为了单人也能练全流程，`All-Projects` 的 `label-Code-Review` 已从 `-1..+1` 放宽到 `-2..+2 group Registered Users`（只在本实验室生效，别照搬到生产）。

### 8.4 认证口径

- `auth.type = LDAP`，`ldap.server = ldap://192.168.200.12:389`，`accountBase = ou=people,dc=corp,dc=local`，`accountPattern = (uid=${username})`；
- 账号**首次登录自动创建**，姓名取 `cn`、邮箱取 `mail`（所以 `dev01` 登录后叫「陈开发」）；
- **不要再试** `auth.type = HTTP` / `HTTP_LDAP`：它们不会自动建号，git push 又走 Gerrit 自带的 HTTP password（和 LDAP 口令不是一回事，必然报 `password does not match the one stored in Gerrit`）；
- **不要再试** `gerrit.war init --dev`：3.9 的 batch/交互模式都不会打开 `DEVELOPMENT_BECOME_ANY_ACCOUNT`，也不会建 admin；
- **不要再试** `scp` 取钩子、`PUT /a/accounts/self/password`（3.9 该端点 404）。

### 8.5 练脏了怎么重置（一条命令）

```bash
/root/gerrit-lab-reset.sh
```

它做的事：停容器 → 删掉 `lab.git` → 从 `/data/gerrit/seed/lab.bundle` 重新克隆（只留 `Initial commit`）→ 清空 changes 索引（避免残留「幽灵 change」）→ 起容器、等 `ready` → 回显 Web 200 与当前 HEAD。所有 change 记录、合入历史、乱推的提交一起消失，**其它项目不受影响**。

想只清某一条 change：Web 上点 **Abandon**（已合入的不能删，只能 `revert`）。

### 8.6 备份与升级

- 升级/重装前备份三样：`/data/gerrit/etc`、`/data/gerrit/git`、`/data/gerrit/bin/gerrit.war`；
- 容器内**没有** `java` 之外的运维工具（连 `ssh-keygen` 都没有），所有 Gerrit 管理命令都要 `podman exec gerrit java -jar /var/gerrit/bin/gerrit.war ...`；
- 站点 `init` 时如果 JRE 镜像缺 `ssh-keygen`，先在宿主 `/data/gerrit/etc` 用宿主 `ssh-keygen` 生成 `ssh_host_rsa_key` / `ssh_host_ed25519_key`，再 `init` 就跳过生成。

---

## 9. 本次实测记录（2026-11-27）

| 场景 | 结果 |
| --- | --- |
| LDAP 首次登录自动建号 | `dev01`→account 1000000、`lead01`→1000001、`qa01` 正常 |
| dev01 push `refs/for/master` | `remote: SUCCESS`，生成 change，`master` 不变 |
| lead01 `+2` + Submit | change 变 `Merged`，`master` 前进；`git pull` 能看到改动 |
| 同基线两条 change 改同一行 | 都推成功；先合一条后，另一条 `git rebase origin/master` 必冲突（`both modified`） |
| 冲突解决后重推 | 同一 `Change-Id` → `Patch Set 2`，重新 `+2` 后合入，`shared_value` 为最终值 |
| Windows 侧全流程 | `ssh-keygen`（无口令）→ 粘贴公钥 → clone → `curl` 取钩子 → push → 打分 → 合入，全部通过 |
| 一键重置 | 推一条 change 后执行 `/root/gerrit-lab-reset.sh`：`master` 回到 `49e5bf9`、change 列表清空、Web 200 |
| 反向确认 | `scp` 取钩子、`auth.type=HTTP*`、`init --dev` 均确认不可用（见 8.4） |
