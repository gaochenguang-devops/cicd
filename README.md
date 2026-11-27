# 单节点 CI/CD 平台

一台 8C/22G 的 Rocky Linux 主机上，用 kubeadm 拉起单节点 Kubernetes，再叠一套完整的「代码 → 镜像 → 制品 → 部署」链路：**GitLab（源码与流水线）+ GitLab Runner（构建）+ Harbor（镜像）+ SonarQube（质量门禁）+ Artifactory（制品）+ ArgoCD（GitOps 部署）+ Keycloak/OpenLDAP（统一账号）**，外加 MetalLB + nginx 网关的统一 HTTPS 入口与 Prometheus/Grafana/Alertmanager 监控栈。

一次 `git push` 到新镜像上线的实测耗时约 **2–3 分钟**（首次构建 72 s + Sonar 扫描 20–35 s + 制品打包 6 s + 清单回写 2 s + ArgoCD 同步；镜像层命中缓存时构建可降到 10 s 以内）。

> 本仓库可作为公开文档仓：所有口令、密钥、Token、机器人地址都已外部化到 `.env`（不入库），仓库内只保留变量名。详见 [6. 凭据与安全](#6-凭据与安全)。

---

## 目录

1. [概览](#1-概览)
2. [快速开始](#2-快速开始)
3. [架构](#3-架构)
4. [入口与端口](#4-入口与端口)
5. [账号与权限](#5-账号与权限)
6. [凭据与安全](#6-凭据与安全)
7. [仓库结构与文档索引](#7-仓库结构与文档索引)
8. [日常运维](#8-日常运维)
9. [容量与已知缺口](#9-容量与已知缺口)
10. [版本矩阵](#10-版本矩阵)
11. [使用约束与坑位](#11-使用约束与坑位)

---

## 1. 概览

| 维度 | 现状 |
| --- | --- |
| 形态 | 单节点（`192.168.200.12`），控制面 + 全部业务组件同机；无高可用 |
| 部署方式 | GitLab / Runner / OpenLDAP / phpLDAPadmin 在宿主机（RPM / systemd / podman）；其余组件在 K8s |
| 入口 | 日常走 `https://<服务>.corp.local`（MetalLB VIP `192.168.200.210` + nginx 网关 + 内部 CA 通配符证书，13 个域名）；NodePort 保留为运维应急 |
| 账号 | OpenLDAP 为唯一账号源 → Keycloak 联邦并签发 OIDC → 5 个系统登录；Artifactory 因 OSS 版限制走 LDAP 直连 |
| 变更流 | `push main` → 4 stage 流水线 → 写 `deploy` 分支 → ArgoCD 同步 → Pod 滚动更新 |
| 观测 | 21 个抓取目标、13 条入口黑盒探测、18 条告警规则、4 张 Grafana 看板；告警经 bridge 进钉钉群 |
| 镜像/制品 | 镜像只进 Harbor（`apps` / `library` 两个项目），二进制制品只进 Artifactory（`build-artifacts`），两者不重叠 |

---

## 2. 快速开始

### 2.1 客户端准备（一次性）

1. **hosts**：把 13 个域名指向 VIP `192.168.200.210`（Windows `C:\Windows\System32\drivers\etc\hosts`）。
2. **信任内部 CA**：导入仓库根目录的 `corp-ca.crt`（`CORP Internal CA`，指纹 `E116E0323765C73653B71B57F27FDB4F2C0DDCFD`，有效期至 2036-11-24）。
3. 浏览器访问 `https://gitlab.corp.local`，点「Keycloak 统一登录」。

完整步骤（含 Windows 证书导入命令、Host 头校验）见 [`docs/01-入口与网络/访问层与证书.md`](docs/01-入口与网络/访问层与证书.md) 第 7 节。

### 2.2 本机跑命令

```powershell
# 依赖：Python 3 + paramiko；凭据全部从 .env 读（无默认口令）
cp .env.example .env        # 填真实值；.env 已被 .gitignore 忽略

python scripts\tools\ssh_exec.py --ping                        # 连通性
python scripts\tools\ssh_exec.py "kubectl get nodes; kubectl get pods -A | head"
python scripts\tools\ssh_exec.py --script scripts\gateway\422-verify-routes.sh --timeout 180
```

- `--script` 执行的脚本里若有 `__VAR__` 占位，`ssh_exec.py` 会**先按 `.env` 渲染再上传**，不需要手工替换。
- 其它脚本单独跑：`python scripts\secrets\render.py <脚本> --out rendered\x.sh`。

### 2.3 三条最常用的健康检查

```powershell
# 统一入口：13 域名状态码 + 证书链 + 301 + 421
python scripts\tools\ssh_exec.py --script scripts\gateway\422-verify-routes.sh --timeout 180

# 监控栈：21 target + 18 规则 + 13 黑盒探测 + 4 看板 + 钉钉桥
python scripts\tools\ssh_exec.py --script scripts\monitoring\521-verify.sh --timeout 300

# 一次完整发版（4 stage 全绿 + ArgoCD 上线）
python scripts\tools\ssh_exec.py --script scripts\pipeline\103-e2e2.sh --timeout 600
```

---

## 3. 架构

### 3.1 分层

```
┌────────────────────────── 账号基座（一套账号登所有系统） ──────────────────────────┐
│  OpenLDAP :389（podman，dc=corp,dc=local，12 账号 / 4 组）                          │
│      │ 只读联邦（READ_ONLY）                                   │ 直连（OSS 无 OIDC）│
│      ▼                                                        ▼                   │
│  Keycloak :30087（realm corp，LDAP User Storage）        Artifactory :30092        │
│      │  OIDC：gitlab / jenkins / harbor / sonarqube / argocd-dex                  │
│      │  （phpLDAPadmin :8090 挂在 LDAP 一侧，仅用于网页管账号）                    │
└──────────────────────────────────────────────────────────────────────────────────┘
        │              │               │                │                 │
        ▼              ▼               ▼                ▼                 ▼
   GitLab :80     Jenkins :30088   Harbor :30090   SonarQube :30091   ArgoCD :30080/30082
        │                                                    ▲
        │  GitLab CI（shell runner + podman）                  │ 质量门禁
        ├──── 1. quality-gate ────────────────────────────────┘
        ├──── 2. build-image ──────────────────────► Harbor
        ├──── 3. artifact-publish ─────────────────► Artifactory（build-artifacts）
        └──── 4. update-manifest ──► GitLab deploy 分支 ──► ArgoCD 同步 ──► Pod
                                                                 ├─ ns podinfo（podinfo×2 + redis）
                                                                 └─ ns webapp（frontend + backend）
```

一句话概括：

- **OpenLDAP 是唯一账号源**，Keycloak 只做「联邦 + 发牌」，业务系统不各自建号；
- **GitLab 是流水线的大脑**（源码 + `.gitlab-ci.yml` + `deploy` 分支），Runner 是干活的手；
- **Harbor 存镜像、Artifactory 存制品**，职责不重叠（镜像不进 Artifactory）；
- **Sonar 是上线前的闸门**，ArgoCD 是上线执行者，两者都只认 GitLab；
- **Jenkins 是并行的第二套 CI**：已打通「拉代码 → Sonar 门禁 → Maven 打包 → Jib 推 Harbor → 制品推 JFrog」，但**不写 deploy 分支**，不参与主链路。

### 3.2 部署形态（谁在 K8s，谁在宿主机）

| 组件 | 部署方式 | 入口 | 副本/实例 |
| --- | --- | --- | --- |
| Kubernetes v1.32.13 | kubeadm 单节点，containerd v2.4.2，Calico v3.32.3 | `:6443` | 1 node |
| GitLab CE 19.6.1 | 宿主机 RPM（omnibus，自带 nginx/PG/Redis/Gitaly） | `:80` | — |
| GitLab Runner 19.6.1 | 宿主机 systemd（shell executor + podman，`concurrency=1`） | — | 1 |
| OpenLDAP 1.5.0 | podman 容器 + systemd | `:389` | 1 |
| phpLDAPadmin 0.9.0 | podman 容器 + systemd | `:8090` | 1 |
| Harbor v2.15.4 | K8s `ns harbor`（Helm） | NodePort `30090` | core/jobservice/nginx/portal/registry + db/redis |
| ArgoCD v3.5.9 | K8s `ns argocd` | NodePort `30080` / `30082`（中文代理） | 7 Deployment + 1 StatefulSet |
| Keycloak 26.6 | K8s `ns keycloak` | NodePort `30087` | keycloak + keycloak-db |
| Jenkins lts-jdk21 | K8s `ns jenkins`（JCasC） | NodePort `30088` / `30089` | 1 |
| SonarQube 10.7-community | K8s `ns sonar` | NodePort `30091` | sonarqube + sonar-db |
| JFrog Artifactory OSS 7.104.7 | K8s `ns artifactory` | NodePort `30092` / `30100`（router 8082 为入口） | artifactory + artifactory-db |
| podinfo 6.17.0 | K8s `ns podinfo` | NodePort `30095` | 2 副本 + redis 1 |
| webapp | K8s `ns webapp` | NodePort `30096` | frontend + backend 各 1 |
| MetalLB v0.14.9 | K8s `ns metallb-system` | VIP `192.168.200.210` | controller + speaker |
| gateway（nginx） | K8s `ns gateway` | VIP `:80/443` | 2 副本，ConfigMap 驱动路由与 TLS |
| 监控栈 | K8s `ns monitoring` | 只经网关（Basic Auth） | prometheus / alertmanager / kube-state-metrics / node-exporter / blackbox-exporter / grafana / dingtalk-bridge |
| metrics-server v0.7.2 | K8s `ns kube-system` | ClusterIP | HPA 数据源 |

### 3.3 三条真实链路

**A. 发版链路（改代码 → Pod 换新）**

1. 开发者 push `root/podinfo` 的 `main`；
2. GitLab 触发流水线（Runner 在宿主跑 podman，`concurrency=1`）；
3. `quality-gate`：扫描源码 → Sonar（`SONAR_TOKEN`）→ `sonar.qualitygate.wait=true` 等 `cicd-gate` 结果，ERROR 则整条停；
4. `build-image`：`podman build -f Dockerfile.ci` → 推 Harbor `apps/podinfo:<sha>` → 回读 registry manifest 必须 200；
5. `artifact-publish`：取出二进制 → tar.gz + sha256 → 传 Artifactory → 读回比对；
6. `update-manifest`：以远端 `deploy` 为基重建提交，改两处 `newTag` 并 push（`resource_group` 保证单写者）；
7. ArgoCD 由 webhook / 轮询发现 `deploy` 变化 → 同步 `podinfo`、`webapp` → 从 Harbor 拉新镜像；
8. 滚动更新完成（提交到 Pod 就绪约 2 分钟）。

**A2. Jenkins 链路（并行第二套，止于推 JFrog）**

`maven-demo-pipeline` 拉 `root/demo-maven` → 共享库 `platform-lib` 执行 Sonar 门禁 → Maven 打包 → Jib 推 `apps/maven-demo:1.0.<构建号>` → jar + sha256 + build-info 推 Artifactory（回读校验）。**不写 deploy 分支、不触发 ArgoCD**。

**B. 登录链路**

```
浏览器 → 各系统「统一登录 / Keycloak」按钮
       → Keycloak :30087/realms/corp（密码校验回源 LDAP，READ_ONLY）
       → 回调各系统 → token 带 groups → 各系统按组授权
```

Artifactory 例外：UI 直接 LDAP bind（同一批账号，无 OIDC）。

**C. 加人链路（只改一处）**

1. phpLDAPadmin（`:8090`）或 `scripts/ldap/ldap-add-user.sh` 建用户并放进组；
2. `ldap-gitlab-sync.timer`（每 10 分钟）把 LDAP 组同步成 GitLab 组/成员，并清退已移出组的人；
3. Keycloak 联邦自动看到新用户，下次登录生效；
4. Artifactory 下次 LDAP bind 直接认得。

---

## 4. 入口与端口

### 4.1 统一 HTTPS 入口（日常走这里）

入口 = MetalLB VIP `192.168.200.210` + `ns gateway` nginx + 内部 CA 的 `*.corp.local` 通配符证书。

| 系统 | 域名 | 后端 | 认证 |
| --- | --- | --- | --- |
| GitLab | `https://gitlab.corp.local` | 宿主 `:80` | Keycloak 或本地 `root` |
| Jenkins | `https://jenkins.corp.local` | `jenkins:80`→8080 | Keycloak 或本地 `breakglass` |
| Harbor | `https://harbor.corp.local` | `harbor:80`→8080 | Keycloak 或本地 `admin` |
| SonarQube | `https://sonar.corp.local` | `sonarqube:9000` | Keycloak 或本地 `sonaradmin` |
| Artifactory | `https://artifactory.corp.local` | `artifactory-router:8082` | LDAP 直连或本地 `admin` |
| ArgoCD | `https://argocd.corp.local` | `argocd-server:80`→8080 | Dex→Keycloak 或本地 `admin` |
| Keycloak | `https://keycloak.corp.local` | `keycloak:80`→8080 | 本地 `admin`（master realm） |
| phpLDAPadmin | `https://ldapadmin.corp.local` | 宿主 `:8090` | LDAP `cn=admin` |
| podinfo / webapp | `https://podinfo.corp.local` / `https://webapp.corp.local` | `podinfo:80` / `frontend:80` | 无（业务演示） |
| Prometheus | `https://prometheus.corp.local` | `prometheus:9090` | 网关 Basic Auth `monitoring` |
| Alertmanager | `https://alertmanager.corp.local` | `alertmanager:9093` | 同上 |
| Grafana | `https://grafana.corp.local` | `grafana:3000` | Grafana 自身登录（网关不叠 Basic） |

当前 13 个域名全部可达（`grafana` 于 2026-11-27 加入，黑盒探测 13/13 up）。已知差异：`gitlab` / `keycloak` 的 302 仍指向旧 http 地址（后端 `external_url` / `KC_HOSTNAME` 未切，属第二阶段，清单见 [`访问层与证书.md`](docs/01-入口与网络/访问层与证书.md) 6.1）。

### 4.2 NodePort 应急通道与宿主端口

| 端口 | 服务 | 归属 | 说明 |
| --- | --- | --- | --- |
| 22 | sshd | 宿主 | 运维入口（`ssh_exec.py`） |
| 80 | GitLab（内置 nginx） | 宿主 | Web、Git over HTTP、OIDC 回调 |
| 389 | OpenLDAP | podman | Keycloak / Artifactory / 运维 |
| 8090 | phpLDAPadmin | podman | 网页管账号 |
| 6443 | kube-apiserver | 宿主 | kubectl |
| 30080 / 30082 | ArgoCD 原生 / 中文代理 | `argocd` | 官方 UI 无多语言，中文由 `30082` 的 nginx 代理注词库实现 |
| 30087 | Keycloak | `keycloak` | 5 个系统 OIDC |
| 30088 / 30089 | Jenkins Web / JNLP agent | `jenkins` | — |
| 30090 | Harbor | `harbor` | `podman push/pull`、ArgoCD 拉镜像 |
| 30091 | SonarQube | `sonar` | 浏览器、CI 扫描器 |
| 30092 / 30100 | Artifactory | `artifactory` | CI 制品上传 |
| 30095 / 30096 | podinfo / webapp | `podinfo` / `webapp` | 业务访问 |
| 210:80/443 | 统一入口 | `gateway` | MetalLB LoadBalancer（VIP） |

> 没有引入 Ingress Controller / Gateway API：单节点上装 NGF 要多 5 个 CRD 和两套控制面镜像，收益不划算（取舍见 [`访问层与证书.md`](docs/01-入口与网络/访问层与证书.md) 1.2）。监控控制台不暴露 NodePort，只经网关 + Basic Auth。

---

## 5. 账号与权限

OpenLDAP（`dc=corp,dc=local`）是唯一账号源：`ou=people` 12 个 `inetOrgPerson`（10 个标准 `uid=` + 2 个历史 `cn=` 条目），`ou=groups` 用 `groupOfNames`。Keycloak 把它挂成 **User Storage（READ_ONLY）**，自己不存密码，`groups` client scope 把组写进 token。

| 账号 | 组 | Harbor（`apps`） | GitLab（`root/podinfo`） | ArgoCD | Sonar | Artifactory |
| --- | --- | --- | --- | --- | --- | --- |
| lead01 | platform-admins | 系统管理员 | 实例管理员 + maintainer | admin | admin | LDAP 可登录 |
| ops01 / ops02 | devops | maintainer | maintainer | admin | admin | LDAP 可登录 |
| dev01 ~ dev05 | developers | developer | developer | readonly | scan | LDAP 可登录 |
| qa01 / qa02 | qa | guest | reporter | readonly | scan | LDAP 可登录 |

登录入口：GitLab 点「Keycloak 统一登录」；ArgoCD 点 **LOG IN VIA DEX**（用户名填 `uid`）；Sonar 点「Log in with Keycloak」；Harbor 点「OIDC」。

新建权限组 / 分区：网页模板 `Corp: Permission Group` / `Generic: Organisational Unit`，或 `scripts/ldap/ldap-add-group.sh`、`ldap-add-ou.sh`。新组默认零权限，需在 GitLab、Harbor 项目成员、ArgoCD `policy.csv`、Sonar 组授权四处登记（Artifactory OSS 无法按组授权，见 [9.2](#92-已知缺口)）。

逐步操作见 [`LDAP新增用户手册.md`](docs/03-身份与账号/LDAP新增用户手册.md)，机制与权限矩阵见 [`OpenLDAP目录.md`](docs/03-身份与账号/OpenLDAP目录.md)。

---

## 6. 凭据与安全

### 6.1 `.env` 是唯一真实值来源（不入库）

| 载体 | 写法 | 怎么变回真实值 |
| --- | --- | --- |
| 本 README / `docs/*.md` | `${HARBOR_ADMIN_PASS}` | `set -a; source .env; set +a`（或 PowerShell 逐行导入） |
| `manifests/*.yaml` | `${...}` | `envsubst`，或 `python scripts/secrets/render.py xx.yaml --out rendered/xx.yaml` |
| `scripts/**/*.sh` | `__HARBOR_ADMIN_PASS__` | `python scripts/secrets/render.py xx.sh --out rendered/x.sh`（Windows/Linux 通用；Linux 也可 `render.sh`） |

```powershell
cp .env.example .env        # 填真实值；.env 已被 .gitignore 忽略
python scripts\secrets\render.py --check --quiet     # 校验占位符是否都能解析
python scripts\secrets\scan.py                        # 泄露扫描：SECRET 应为 0 处
```

- **`scripts/tools/ssh_exec.py` 自动渲染**：`--script` / `--file` / 命令行里的 `__VAR__` 上传前替换，SSH 口令也从 `.env` 读。
- **守卫钩子**（装一次，之后 git 自动查）：
  ```powershell
  pwsh scripts\secrets\install-hooks.ps1     # Windows（含 BOM，PS 5.1 也能跑）
  bash scripts/secrets/install-hooks.sh      # Linux / Git Bash
  ```
  `pre-commit` 挡 `.env` 与暂存内容里的明文凭据；`pre-push` 扫全部提交历史。
- **出公开仓前先生成匿名副本**（原仓库零改动）：
  `python scripts\secrets\scan.py --anonymize --outdir ..\cicd-public`（IP→`198.51.100.0/24`、`*.corp.local`→`*.example.com`、robot/账号名→通用名）。

审计结论与处置记录见 [`凭据与泄露审计.md`](docs/06-安全与发布/凭据与泄露审计.md)。

### 6.2 凭据变量清单（真实值只在 `.env`）

| 用途 | 账号 / 键 | 变量 |
| --- | --- | --- |
| 宿主 SSH | `root@192.168.200.12:22` | `SSH_ROOT_PASS` |
| GitLab | `root` | `GITLAB_ROOT_PASS` |
| GitLab PAT（ArgoCD 读仓、Jenkins 推送） | `root` | `GITLAB_PAT` |
| Harbor | `admin` | `HARBOR_ADMIN_PASS` |
| Harbor 推送（GitLab CI） | `robot$apps+ci-builder` | `HARBOR_ROBOT_CI_SECRET` |
| Harbor 推送（Jenkins） | `robot$apps+jenkins-ci` | `HARBOR_ROBOT_JENKINS_SECRET` |
| Harbor 只读（library 基础镜像） | `robot$library+jenkins-lib-pull` | `HARBOR_ROBOT_LIB_SECRET`（审计结论：冗余待删） |
| SonarQube | `sonaradmin` / CI 令牌 | `SONAR_ADMIN_PASS` / `SONAR_CI_TOKEN` |
| Artifactory | `admin` | `ARTIFACTORY_ADMIN_PASS` |
| Jenkins 应急 | `breakglass` | `JENKINS_BREAKGLASS_PASS` |
| Keycloak | `admin`（master） | `KEYCLOAK_ADMIN_PASS` |
| Grafana | `admin` | `GRAFANA_ADMIN_PASS` |
| OpenLDAP | `cn=admin,dc=corp,dc=local` / 用户初始口令 | `LDAP_ADMIN_PASS` / `LDAP_USER_INIT_PASS` |
| 网关 Basic Auth（Prometheus / Alertmanager） | `monitoring` | `GATEWAY_BASIC_PASS` |
| ArgoCD | `admin` | `ARGOCD_ADMIN_PASS` |
| 7 个 OIDC client secret | GitLab / Jenkins / Harbor / ArgoCD-Dex / Sonar / Artifactory / cli-test | `*_OIDC_SECRET` |
| 组件数据库口令 | Keycloak / Sonar / Artifactory | `KEYCLOAK_DB_PASS` / `SONAR_DB_PASS` / `ARTIFACTORY_DB_PASS` |
| 钉钉告警机器人（加签） | webhook + 密钥 | `DINGTALK_WEBHOOK_URL` / `DINGTALK_SECRET` |

### 6.3 改口令时必须同步的位置

| 改什么 | 必须同步 |
| --- | --- |
| Harbor admin 口令 | 无（CI 用 robot 账号） |
| Sonar 令牌 | GitLab 变量 `SONAR_TOKEN` + Jenkins 凭据 `sonar-token` |
| GitLab PAT | GitLab 变量 `GITLAB_PAT` + Jenkins 凭据 `gitlab-pat` + ArgoCD repo 凭据 |
| Grafana admin | Secret `monitoring/grafana-admin` → `rollout restart deploy/grafana`（env 注入，改完必须重启） |
| 网关 Basic Auth | 改 `ns gateway` 的 htpasswd → `rollout restart deploy/gateway` |

完整台账（三处凭据全量审计、4 项待收敛动作、轮换 SOP）见 [`CI凭据治理.md`](docs/02-流水线与交付/CI凭据治理.md)。

---

## 7. 仓库结构与文档索引

### 7.1 目录

```
cicd/
├── README.md                 # 本文件：现状总览
├── .env / .env.example       # 真实凭据（忽略） / 模板（入库）
├── .gitignore
├── .githooks/                # pre-commit / pre-push 守卫
├── corp-ca.crt               # 内部 CA（公开证书，非私钥）
├── docs/                     # 19 篇正文，按 6 类组织
│   ├── README.md             # 文档索引 + 30 分钟阅读顺序 + 维护约定
│   ├── 01-入口与网络/  02-流水线与交付/  03-身份与账号/
│   ├── 04-可观测与告警/  05-组件与测试/  06-安全与发布/
├── manifests/                # K8s 清单（monitoring / gateway / keycloak / jenkins / sonar / artifactory / podinfo / webapp）
├── scripts/                  # 按组件分组的脚本；索引与执行方式见 scripts/README.md
│   ├── secrets/              # render.py / scan.py / 钩子安装脚本
│   └── tools/                # ssh_exec.py 等
├── jenkins-pipeline/         # Jenkinsfile + shared-library
└── repo-overlay/             # GitLab 侧 .gitlab-ci.yml 等 overlay
```

### 7.2 文档索引

| 分类 | 文档 | 一句话 |
| --- | --- | --- |
| 索引 | [`docs/README.md`](docs/README.md) | 6 类分类、30 分钟阅读顺序、维护约定、审计记录 |
| 01 入口与网络 | [`访问层与证书.md`](docs/01-入口与网络/访问层与证书.md) | MetalLB VIP + 内部 CA + nginx 网关，13 域名路由与客户端接入 |
| 01 入口与网络 | [`CI-CD网络流量.md`](docs/01-入口与网络/CI-CD网络流量.md) | 一次 push 的 9 步链路与四层网络走向，排障五步 |
| 01 入口与网络 | [`生产架构与改造路线.md`](docs/01-入口与网络/生产架构与改造路线.md) | 现状与生产态差距、5 条组合原则、P0~P3 路线与执行记录 |
| 02 流水线与交付 | [`CI-CD流水线.md`](docs/02-流水线与交付/CI-CD流水线.md) | 4 个 stage 每一跳做什么、清单与踩坑 |
| 02 流水线与交付 | [`GitOps与ArgoCD.md`](docs/02-流水线与交付/GitOps与ArgoCD.md) | `main`/`deploy` 分支模型、门禁、并发保护、回滚 |
| 02 流水线与交付 | [`部署与回滚.md`](docs/02-流水线与交付/部署与回滚.md) | 从裸机到 GitLab×ArgoCD 跑通的全记录、组件拓扑与容量 |
| 02 流水线与交付 | [`Jenkins部署.md`](docs/02-流水线与交付/Jenkins部署.md) | Jenkins 部署、JCasC、OIDC 安全域、权限矩阵 |
| 02 流水线与交付 | [`Jenkins流水线.md`](docs/02-流水线与交付/Jenkins流水线.md) | Pipeline + Shared Library、5 stage、构建排障表 |
| 02 流水线与交付 | [`Sonar与Artifactory.md`](docs/02-流水线与交付/Sonar与Artifactory.md) | 质量门禁 `cicd-gate`、制品上传与校验、故障速查 |
| 02 流水线与交付 | [`镜像与制品拉取.md`](docs/02-流水线与交付/镜像与制品拉取.md) | Harbor / Artifactory / Jenkins 三处归档位置与拉取命令 |
| 02 流水线与交付 | [`CI凭据治理.md`](docs/02-流水线与交付/CI凭据治理.md) | 方案 A、三处凭据审计、4 项待收敛、轮换 SOP |
| 03 身份与账号 | [`统一身份SSO-Keycloak.md`](docs/03-身份与账号/统一身份SSO-Keycloak.md) | realm/LDAP 联邦/OIDC client，逐服务对接与回滚 |
| 03 身份与账号 | [`OpenLDAP目录.md`](docs/03-身份与账号/OpenLDAP目录.md) | 目录结构、组继承、权限矩阵、遗留条目清理 |
| 03 身份与账号 | [`LDAP新增用户手册.md`](docs/03-身份与账号/LDAP新增用户手册.md) | 建号 → 入组 → 同步 → 验证 → 离职 |
| 04 可观测与告警 | [`可观测性.md`](docs/04-可观测与告警/可观测性.md) | 组件与抓取矩阵、能力边界、Grafana 看板、黑盒探测 |
| 04 可观测与告警 | [`告警接入.md`](docs/04-可观测与告警/告警接入.md) | 18 条规则 5 组、分组抑制、钉钉加签接入与 errcode 排障 |
| 05 组件与测试 | [`组件清单.md`](docs/05-组件与测试/组件清单.md) | 七套系统的职责与边界、一次提交走过的链路 |
| 05 组件与测试 | [`验收测试用例.md`](docs/05-组件与测试/验收测试用例.md) | 链路用例、实测时序、回归清单 |
| 06 安全与发布 | [`凭据与泄露审计.md`](docs/06-安全与发布/凭据与泄露审计.md) | 两轮扫描处置、内部信息暴露面、钩子、匿名化、轮换优先级 |
| 脚本 | [`scripts/README.md`](scripts/README.md) | 脚本分组索引、执行方式、凭据占位约定、守卫钩子 |

---

## 8. 日常运维

### 8.1 发版

```bash
# 只需 push main；deploy 分支由 CI 回写，main 不再被回写
cd /root/podinfo-src && git pull && git commit -am "feat: xxx" && git push origin main
```

### 8.2 回滚（秒级，不触发构建）

```bash
git clone http://192.168.200.12/root/podinfo.git && cd podinfo && git checkout deploy
git revert <deploy 提交> --no-edit && git push origin deploy
```

### 8.3 常用回归/排障命令

```powershell
# 环境总览
python scripts\tools\ssh_exec.py "kubectl -n argocd get applications; kubectl -n podinfo get pods; kubectl -n webapp get pods"

# 业务可用性
python scripts\tools\ssh_exec.py "curl -s http://192.168.200.12:30095/version; curl -s -X POST -d '{}' http://192.168.200.12:30096/echo"

# LDAP 现状（12 账号 / 4 组 / 非标准条目）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1120-ldap-dump.sh --timeout 90

# 各系统账号与角色
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1123-users-check.sh --timeout 60

# Sonar / Artifactory 与 4 stage 结果
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1010-final-verify.sh --timeout 60

# CI 凭据审计（GitLab 变量 vs K8s Secret vs Jenkins 凭据）
python scripts\tools\ssh_exec.py --script scripts\ci\600-audit-credentials.sh --timeout 200
```

### 8.4 故障影响面（谁挂了会怎样）

| 服务 | 挂了的影响 |
| --- | --- |
| OpenLDAP | **全站登录失效**（Keycloak、Artifactory 都回源它），已登录会话短期可用 |
| Keycloak | 5 个系统统一登录不可用；本地应急账号仍可进 |
| GitLab | 无法提交/触发流水线/写 deploy；ArgoCD 按现有状态继续运行 |
| Runner | 流水线排队不动，集群保持现状 |
| Harbor | 推拉镜像失败；已在本地的镜像仍可跑（`imagePullPolicy: Always` 除外） |
| Sonar | `quality-gate` 失败 → **流水线阻断**（设计上的「宁可不上线」） |
| Artifactory | 卡在 artifact 阶段，不写 deploy，旧版本继续跑 |
| ArgoCD | 新提交不自动上线，手动 `kubectl apply` 仍可 |
| Jenkins | 只影响它自己，主链路无感 |
| metrics-server | HPA 失效，不影响发布 |

一句话：**LDAP/Keycloak 是「人」的单点，Harbor 是「镜像」的单点，GitLab 是「变更」的单点**；Sonar / Artifactory 失败只会卡住上线，不破坏已运行服务。

---

## 9. 容量与已知缺口

### 9.1 存储与资源

| 位置 | 用途 | 已用 |
| --- | --- | --- |
| `/data/harbor` | registry / db / redis / joblog | 4.0G |
| `/data/sonarqube/{pg,data,plugins}` | PG + ES + 插件 | 403M |
| `/data/jenkins` | Jenkins home（PVC 10Gi） | 304M |
| `/data/artifactory/{pg,data}` | PG + 制品（20Gi/5Gi） | 109M |
| `/data/keycloak` | Keycloak PG（5Gi） | 69M |
| `/data/openldap` | LDAP 数据 | 296K |

宿主：8C / 22G，根盘 64G（已用 52G，约 82%）；内存已用约 14Gi（另有约 7Gi buff/cache）。最吃内存的是 `artifactory`（约 2.4Gi，limit 4Gi）与 `kube-apiserver`（约 640Mi）。运行中 Pod 49 个。

### 9.2 已知缺口

1. **单节点全栈**：控制面、Harbor、GitLab、Keycloak 均单实例，无高可用；Keycloak 一挂六个系统都无法新登录。根盘仅剩约 12G，拉大镜像前先 `podman image prune` 或扩盘。
2. **TLS 只到入口层**：客户端到 VIP 是 https，但 `gitlab` / `keycloak` 的 302 仍指旧 http 地址（`external_url` / `KC_HOSTNAME` 待切）；LDAP 仍是 389 明文。
3. **无 StorageClass / 无 Ingress 抽象**：PV 全为 hostPath 手工建，迁移节点需同步 `/data`；路由改在 `manifests/gateway/20-nginx-config.yaml`，改完必须 `rollout restart`。
4. **备份缺失**：`/data` 六个目录没有定期备份与恢复演练（最该补的一项，仍未做）。
5. **Artifactory OSS 限制**：无 OIDC、无 REST 建仓、无法按仓库授权（`/api/security/*` 返回 Pro-only），只能继续用 `admin`。
6. **Sonar 原始 `admin` 本地密码失效**：现用 `sonaradmin` 应急；`admin` 仅以 CI 令牌形式在流水线生效。`sonar.forceAuthentication=true`，匿名 API 一律 401。
7. **Jenkins 止于推 JFrog**：`maven-demo-pipeline` 已打通 5 stage，但**不自动部署**，且缺 `timestamper/junit/ws-cleanup/maven-plugin` 四个插件（靠 workaround）。
8. **LDAP 目录有越权遗留**：`cn=遗留账号1`（uid `legacy1`）同时属于 `platform-admins` 与 `developers`，另有建在 Base 下的 `cn=test` 越界组，经 Keycloak 会拿到多系统管理员权限；另一个 `cn=legacy2` DN 含空格。**建议优先清理**，步骤见 [`OpenLDAP目录.md`](docs/03-身份与账号/OpenLDAP目录.md) 2.3。
9. **可观测缺日志与业务指标**：已有指标/看板/探测/钉钉告警，仍缺 Loki 日志、Harbor/Jenkins/Sonar 业务指标（需 exporter 或插件）、Grafana 接 Keycloak OIDC；企业微信与 SMTP 通道仍是占位。
10. **CI 收敛只做了一半**：方案 A 已确立、凭据已审计，但 4 项最小权限动作待执行（`GIT_PUSH_TOKEN` 加 Protected、`gitlab-pat` 换 Deploy Token、删冗余 `harbor-lib-pull`、拆分 auth/ci 两个 Secret）。
11. **GitLab 已关 LDAP 直连**（`ldap_enabled=false`），只保留 OIDC；Keycloak 挂了 LDAP 用户无法登录 GitLab，只能用 `root`。

---

## 10. 版本矩阵

| 组件 | 版本 |
| --- | --- |
| 操作系统 / 硬件 | Rocky Linux 10.2，8C/22G，内核 6.12，单机 |
| Kubernetes | v1.32.13（kubeadm 单节点；containerd v2.4.2、Calico v3.32.3、CoreDNS v1.11.3） |
| GitLab CE | 19.6.1（Omnibus RPM，宿主 `:80`） |
| GitLab Runner | 19.6.1（shell executor + podman，`concurrency=1`） |
| Harbor | v2.15.4（Helm，NodePort 30090） |
| ArgoCD | v3.5.9（含 Dex v2.45.1，中文代理 30082） |
| Keycloak | 26.6（realm `corp`，LDAP 联邦 READ_ONLY） |
| OpenLDAP / phpLDAPadmin | osixia/openldap 1.5.0 / 0.9.0（podman） |
| Jenkins | lts-jdk21（JCasC，NodePort 30088/30089） |
| SonarQube | 10.7-community + sonar-auth-oidc-plugin 2.1.1 |
| JFrog Artifactory | OSS 7.104.7 |
| PostgreSQL | 16（Keycloak / Sonar / Artifactory / Harbor 各自独立实例） |
| 监控栈 | Prometheus + Alertmanager + kube-state-metrics + node-exporter + blackbox-exporter v0.25.0 + Grafana 11.3.0 |
| 业务应用 | podinfo 6.17.0；webapp（自建三层，复用同一镜像） |

---

## 11. 使用约束与坑位

1. **服务器不能直连 Docker Hub / GitHub**：镜像走 `docker.m.daocloud.io`（docker.io）、`m.daocloud.io`（registry.k8s.io）；GitHub 代码走 `gh-proxy.com` 前缀代理。
2. **containerd 2.x 仓库配置**必须写在 `[plugins.'io.containerd.cri.v1.images'.registry] config_path = '/etc/containerd/certs.d'`，旧写法不生效。
3. **Harbor `apps` 项目私有**：集群里每个命名空间都要一份 `harbor-regcred`（`podinfo`、`webapp`、`kube-system` 已建）。
4. **Windows 下避免 `$()`**：PowerShell 会先行展开，复杂命令写成 `.sh` 用 `--script` 执行。
5. **LDAP 组成员变更后要重新登录**：各系统靠登录时的 `memberOf` / `groups` 刷新（`memberof` overlay 由 Harbor 读取）；GitLab CE 无 LDAP 组同步，组权限由 `ldap-gitlab-sync.timer` + API 赋权。
6. **改网关路由或 Grafana 口令必须重启对应 Deployment**：CM/Secret 是启动时注入，不重启不生效。
7. **改 `datasource` / 看板后要 reload**：Grafana provisioning 目录挂载，改 CM 后等 kubelet 同步（约 40–60 s）再重启 Pod。

> 文档维护约定：新增/停用任何组件，先改本文件「概览 / 部署形态 / 入口表」，再同步对应 `docs/` 正文，最后跑一次 `python scripts\secrets\scan.py` 与文档断链检查。详细索引与阅读顺序见 [`docs/README.md`](docs/README.md)。
