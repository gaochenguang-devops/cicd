# 脚本索引

2026-11-26 做过一次精简：**只保留还会被复用的脚本**，一次性排错/取证脚本（345 个）全部从目录移除。原始全量已打包，需要查历史取证过程时解压即可：

```
_archive\scripts-full-backup-20261126.zip     # 480 个文件的完整快照（含已精简掉的 345 个）
```

现有 17 个目录、220 个脚本（+ 本索引）：

| 目录 | 组件 | 文件数 | 内容 |
|---|---|---|---|
| `tools\` | 工具 / 入口 | 3 | `ssh_exec.py` 远程执行器、`bootstrap.sh` / `bootstrap.ps1` 一键分步重跑 |
| `k8s\` | Kubernetes 节点 | 11 | 系统准备、kubeadm、CNI、重启验收、metrics-server 四连修 |
| `argocd\` | ArgoCD | 15 | 安装、接 GitLab、webhook、中文层、SSO 终态核查、切 deploy 分支、Dex 桥接 |
| `gitlab\` | GitLab CE | 10 | 安装、初始化、演示仓库、OIDC 切换与验证、端到端登录 |
| `harbor\` | Harbor | 9 | Helm 安装、Redis/PVC、权限修复、冒烟、OIDC 切换与验证 |
| `runner\` | GitLab Runner | 11 | 注册、拉源码、推 CI、触发与等待、部署、镜像拉取修复、自检 |
| `pipeline\` | CI/CD 链路回归 | 23 | 公共断言库、TC 分组用例、一键回归、现场复位、日常体检、webhook/清单维护 |
| `app\` | 业务应用 | 4 | webapp 三层源码、推送、部署、验收 |
| `ldap\` | LDAP 统一账号 | 14 | 建号/建组/建 OU、组同步实现、部署与模板、回归与对账 |
| `jenkins\` | Jenkins | 50 | 镜像、部署、授权矩阵、OIDC 切换、JCasC reload、登录验证；`350~391` 为 Pipeline + 共享库落地（Maven 装 PVC、Harbor robot、建库建 Job、六轮构建排障、凭据迁 Secret、端到端验证） |
| `keycloak\` | Keycloak | 10 | 部署、realm、client 批量创建、parentId 修复、组映射、Dex client、硬化 |
| `sonar-jfrog\` | Sonar + Artifactory | 23 | 镜像转存、部署、OIDC、质量门、CI 推送、端到端验收、全量盘点 |
| `verify\` | 对接验证 | 6 | 三服务登录对比、Dex 端到端、groups、RBAC 终验、配置导出、client 清单 |
| `probe\` | 探针 | 1 | `probe.sh` 通用环境探测（只留这一个） |
| `gateway\` | 统一入口（MetalLB + nginx 网关） | 23 | `400~404` 集群/镜像/SVC 盘点、`410~413` MetalLB 安装与 IP 池 + LB 探针、`420` 内部 CA 与证书、`421` 网关部署、`422/423` 路由回归与诊断、`424~427` fd 限制 / ldapadmin 502 / 直连宿主修法、`428` 全域名复测、`429~433` 网关重启溯源、resolver 方案试探、ClusterIP 切换与 IP 漂移检查、`verify\960` 整体验收 |
| `monitoring\` | 可观测 | 11 | `500~503` 抓取目标与镜像源探测（含 ksm 镜像可用源结论）、`510` 镜像转存、`520` 部署、`521~523` 验证（目标/规则/控制台/桥接）、`524/525` TSDB 锁修复与告警链路自测 |
| `ci\` | CI 收敛与凭据 | 2 | `600` GitLab 变量 vs K8s Secret vs Jenkins 凭据审计、`601` 给 Job 打「独立任务」标注 + 凭据清单核对 |

执行方式（远端脚本经 `ssh_exec.py` 直接流式执行，无需先上传）：

```powershell
cd C:\Users\morning\Desktop\cicd
python scripts\tools\ssh_exec.py "kubectl get nodes"
python scripts\tools\ssh_exec.py --script scripts\k8s\19-post-reboot.sh --timeout 200
python scripts\tools\ssh_exec.py --put "scripts\pipeline\lib-test.sh=>/root/cicd-test/lib-test.sh"
```

注意：**含引号、`$`、反斜杠或 JSON 的命令一律写成 `.sh` 再 `--script`**，否则 argparse 与 shell 二次展开会吞参数。

---

## 日常只用这几条

| 场景 | 命令 |
|---|---|
| 平台体检（应用/镜像/端口/HPA） | `--script scripts\pipeline\239-state-check.sh` |
| 全量盘点（K8s / 宿主 / 各系统配置） | `--script scripts\sonar-jfrog\1100-inventory-k8s.sh` / `1101-inventory-host.sh` / `1109~1112` |
| LDAP 与账号对账 | `--script scripts\sonar-jfrog\1120-ldap-dump.sh` / `1123-users-check.sh` |
| 流水线 + 制品 + ArgoCD 一致性 | `--script scripts\sonar-jfrog\1010-final-verify.sh` |
| 新建 LDAP 用户 | `--script scripts\ldap\ldap-add-user.sh`（参数见 `docs/03-身份与账号/LDAP新增用户手册.md`） |
| 回归测试（约 15 分钟，末尾自动复位） | `--script scripts\pipeline\run-all.sh --timeout 1200` |
| 测试中断后恢复基线 | `--script scripts\pipeline\99-restore.sh` |
| **入口层回归（13 域名 / 证书链 / 301 / 421）** | `--script scripts\gateway\422-verify-routes.sh` |
| **可观测回归（目标 / 规则 / 鉴权 / 桥接）** | `--script scripts\monitoring\521-verify.sh` |
| **CI 凭据审计** | `--script scripts\ci\600-audit-credentials.sh` |

## 各目录要点

**tools\**：`ssh_exec.py` 支持 `--script` / `--put` / `--ping`。`bootstrap.sh`/`.ps1` 只覆盖"从零装机到 GitLab+ArgoCD 打通"这 14 步（`probe` → `k8s 01~04` → `argocd 05` → `gitlab 08~11` → `argocd 12/15/16/17`），后续组件不在其中，按需手动跑。

**k8s\**：`01-prepare`（swap/内核/containerd）→ `02-precheck-images` → `03-kubeadm-init` → `04-cni`（Calico）。`18-enable-and-reboot` 会重启机器，不纳入自动流程；`19-post-reboot` 重启后核对。`96/98/100` 是 metrics-server 的补丁（`--kubelet-insecure-tls`、ClusterRole、端口参数），`97/99` 是配套日志与二次诊断。

**argocd\**：`05` 安装（`server.insecure=true`）、`12` 接 GitLab 建 Application、`15/16` webhook 诊断与验证、`17` 收尾、`20` 端到端复测、`21/22` 中文代理层、`91/101` 健康检查、`210` SSO 终态读回、`228` 切 `deploy` 分支、`230/237/238` 是 OIDC 与 Dex 桥接的切换脚本（当前生效的是 Dex 桥接）。

**gitlab\**：`08/09/10/11` 装机链路；`041/042` 切 OIDC 与验证；`055/080` 端到端登录复测；`040` 改 RBAC 前备份 `gitlab.rb`；`30` 前置盘点。GitLab 已关 LDAP 直连，直连时代的 30 多个诊断脚本已归档。

**harbor\**：`66` Helm 安装、`67` 校验、`68` valkey PVC、`69` NodePort 收尾、`71` 修 hostPath 权限、`72` push/pull 冒烟；`511/512/515` 是 OIDC 配置与验证（`auth_mode=oidc_auth`）。

**runner\**：`73` 安装、`74` 拉 podinfo、`75/76` 注册与修参数、`77` 推 CI 与变量、`78/81` 触发与等待、`83/84` 预检与部署、`86` containerd 拉取修复、`89` 自检。

**pipeline\**：`lib-test.sh` 断言库 + `run-all.sh` 一键回归 + `99-restore.sh` 复位是核心；`40~57` 是 TC 分组用例（首版与校准版并存）；`102/103/104/111` 端到端验收；`230` webhook 注册、`237` 改造后验证、`239` 日常体检、`245` deploy 分支两份 application.yaml 对齐。

**ldap\**：`ldap-add-user.sh`（自动取号 + 入组 + 触发同步）、`ldap-add-group.sh`、`ldap-add-ou.sh`、`ldap-gitlab-sync.sh`（服务器 `/usr/local/bin/` 同名 + systemd timer，10 分钟一次）；`posixAccount.xml` / `groupOfNames.xml` 是 phpLDAPadmin 模板；`120~122` 部署链路，`170/175` 网页与同步定时器，`188/192/193` 回归与对账。

**jenkins\**：`304` 转存镜像、`307` 部署（PVC 10Gi + JCasC ConfigMap）、`316` 热重载切换授权矩阵、`322/323` 权限验证、`336` 切 OIDC、`338` reload JCasC、`340` OIDC 后验证。
`350~383` 是 Pipeline + `platform-lib` 落地链路：`350~352` 探测（Maven/能力/镜像源）→ `353` 装 Maven 进 PVC → `354/355/357` 基础镜像与两个 Harbor robot → `356/358` 建 GitLab 仓库并推源码 → `359~367` JCasC 合并的失败留档与最终修法 → `368` 建 Job（含 config.xml 全文）→ `369~377` 六轮构建与修法推送 → `378~383` 端到端验证（镜像/制品/sha256/门禁/集群拉取/清理）。详见 `docs/02-流水线与交付/Jenkins流水线.md`。

**keycloak\**：`402/405` 部署（Postgres + Keycloak）、`406` realm、`416` 建 4 个 client + `groups` scope、`422` 修 parentId、`423` 组映射器、`429/430` argocd-dex client 与 scope、`431/432` 关闭口令模式。

**sonar-jfrog\**：`960/961` 镜像与部署、`966/968/991` OIDC 三段、`994/996` 建组授权与质量门、`998/1009` 推 CI 文件与变量、`1004/1006/1010` 验收、`1100~1112` 盘点、`1120~1123` LDAP 与账号导出。

**verify\**：`900` 三服务登录对比、`926/928` Dex 端到端与 groups、`932` RBAC 终验、`950` 一次导出四份配置、`951` 列 client 状态。

---

## 环境事实（脚本依赖）

- ArgoCD API：`http://192.168.200.12:30080`（`server.insecure=true`，HTTP 非 HTTPS）；中文层 `:30082`
- 刷新方式：`kubectl annotate application <name> argocd.argoproj.io/refresh=hard --overwrite`（REST 无 refresh 端点，`/refresh` 返回 404）
- 删除应用：`DELETE /api/v1/applications/<name>?cascade=true` 且必须带 `Content-Type: application/json`
- 凭据缓存：改 Secret 后需重启 `argocd-repo-server` 才会重新 clone 校验
- LDAP：`ldap://192.168.200.12:389`，admin `cn=admin,dc=corp,dc=local`/`${LDAP_ADMIN_PASS}`，业务账号初始密码 `${LDAP_USER_INIT_PASS}`；**12 个账号 = 10 个标准 `uid=` + 2 个历史 `cn=` 条目，另有 `cn=test` 越界组**（见 `docs/03-身份与账号/OpenLDAP目录.md` 2.3）
- **认证现状（2026-11-26）**：GitLab `ldap_enabled=false` 只走 `openid_connect`；Harbor `auth_mode=oidc_auth`；Jenkins `oicSecurityRealm`；Sonar `sonar.auth.oidc.*`；ArgoCD 走 Dex 的 `oidc` connector；**Artifactory 是唯一 LDAP 直连**。Keycloak `http://192.168.200.12:30087`，`admin`/`${KEYCLOAK_ADMIN_PASS}`，realm `corp`（UUID `b145c645-01c7-414c-9860-ec765bc46ba2`）
- Jenkins：`http://192.168.200.12:30088`（agent `30089`），home `/data/jenkins`（hostPath PV 10Gi），配置由 ConfigMap `jenkins-casc` 驱动（reload `/configuration-as-code/reload`），镜像 `192.168.200.12:30090/library/jenkins:lts-jdk21`；全局授权策略的 JSON 键是 **globalMatrix**（写 `matrix` 会启动崩溃）；`numExecutors=2`
- SonarQube：`http://192.168.200.12:30091`，本地应急管理员 `sonaradmin`/`${SONAR_ADMIN_PASS}`（原 `admin` 本地密码失效），CI 令牌 `${SONAR_CI_TOKEN}`（属 `admin`）；`sonar.forceAuthentication=true`（匿名 API 一律 401）
- Artifactory：`http://192.168.200.12:30092`（UI `/ui/`，router 8082；备用 NodePort 30100），`admin`/`${ARTIFACTORY_ADMIN_PASS}`，仓库 `build-artifacts`；OSS 版只能走 `/artifactory/api/...` + Basic，组权限只能在 UI 建
- 宿主容量：16 GiB 已用约 12 GiB；根盘 64 G 已用 45 G（72%），`/data` 中 harbor 4.0 G、sonarqube 403 M、jenkins 304 M、artifactory 109 M、keycloak 69 M
- `pipeline\` 下的用例引用 `/root/cicd-test/lib-test.sh`，上服务器前先 `--put` 这些文件到该目录
---

## 凭据与占位符（上传 GitHub 前请读）

脚本里的口令/令牌全部写成了 `__VAR__` 形式（如 `__HARBOR_ADMIN_PASS__`），**不再是明文**。

**Windows 和 Linux 用同一个入口：`scripts/secrets/render.py`（Python 3，无第三方依赖）**

```powershell
# Windows / PowerShell
python scripts\secrets\render.py scripts\monitoring\705-final-verify.sh > $env:TEMP\705.sh
python scripts\secrets\render.py "scripts\**\*.sh" --outdir rendered --flatten   # 批量
python scripts\secrets\render.py --check --quiet                                 # 只校验，不打印真值
python scripts\tools\ssh_exec.py --script scripts\monitoring\705-final-verify.sh  # 直接跑，内部自动渲染
```

```bash
# Linux / bash（等价写法，shell 版保留给没有 python 的环境）
bash scripts/secrets/render.sh scripts/monitoring/705-final-verify.sh > /tmp/run.sh
bash /tmp/run.sh
```

- `render.py <file>`：按 `.env` 替换占位符输出到 stdout；`--out` / `--outdir` / `--inplace` 落盘；`--check` 只校验，遇到 `.env` 里没有的键返回 3。
- 占位风格：`*.sh|*.py` 用 `__VAR__`，`*.yaml|*.md` 用 `${VAR}`，`render.py` 按扩展名自动判断；`__VAR__` 在文档里没有意义，`${VAR}` 在 shell 里会被环境变量抢先展开，所以分开。
- **`scripts/tools/ssh_exec.py` 已内置渲染**：`--script` / `--file` / 命令行参数里的 `__VAR__` 上传前自动替换，SSH 口令也从 `.env` 读（`SSH_ROOT_PASS`），远端不需要 `.env`。
- 真实值只在根目录 `.env`；`.gitignore` 已忽略 `.env`、`*.bak`、`*.log`、`*.key/*.pem`、`rendered/`、`__pycache__/`。

## 守卫钩子（pre-commit / pre-push）

一次性安装，之后 git 自动调用：

```powershell
pwsh scripts\secrets\install-hooks.ps1        # Windows
bash scripts/secrets/install-hooks.sh         # Linux / Git Bash
git config --get core.hooksPath                # 应输出 .githooks
```

- `.githooks/pre-commit`：① 暂存区出现 `.env` / `.env.*` 变体直接拒绝；② 用 `scan.py` 扫**暂存版本**（`git show :file`），发现凭据类明文拒绝；③ 占位符在 `.env` 找不到时只警告。
- `.githooks/pre-push`：对 `git rev-list --all` 的每个提交跑模式扫描，历史里有 `glpat-`/`squ_`/私钥/URL 带口令就拒绝推送。
- 只能临时绕过：`git commit --no-verify` / `git push --no-verify`（不建议，绕过就等于没装）。
- 实测：伪造 `glpat-AAAA…` 的提交被 pre-commit 拦下并打印命中位置；正常文档改动放行。