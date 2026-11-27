# 单节点 CI/CD 平台（192.168.200.12）：GitLab · Runner · Harbor · Sonar · Artifactory · ArgoCD · Keycloak

单节点 Kubernetes + GitLab + GitLab Runner + Harbor + ArgoCD，已跑通从 `git push` 到 Pod 上线的完整链路：**Sonar 质量门禁 → Runner 构建 → 推 Harbor → 制品上传 Artifactory → 回写镜像 tag → ArgoCD 拉取部署**。

一次提交到新镜像上线实测约 **2–3 分钟**（首次构建 72 s + Sonar 扫描 20–35 s + 制品打包 6 s + 清单回写 2 s + ArgoCD 同步；镜像层命中缓存时构建可降到 10 s 以内）。

## 访问入口



| 系统           | 地址                                                                               | 账号                                                     |
| ------------ | -------------------------------------------------------------------------------- | ------------------------------------------------------ |
| GitLab       | [http://192.168.200.12](http://192.168.200.12)                                   | `root` / `${GITLAB_ROOT_PASS}`；登录页另有「Keycloak 统一登录」 |
| ArgoCD（中文）   | [http://192.168.200.12:30082](http://192.168.200.12:30082)                       | `admin` / `${ARGOCD_ADMIN_PASS}`；或「Log in via Keycloak」  |
| ArgoCD（原生英文） | [http://192.168.200.12:30080](http://192.168.200.12:30080)                       | 同上                                                     |
| Harbor 镜像仓库  | [http://192.168.200.12:30090](http://192.168.200.12:30090)                       | `admin` / `${HARBOR_ADMIN_PASS}`（本地应急）；业务账号走 Keycloak，项目 `apps` / `library` |
| podinfo 应用   | [http://192.168.200.12:30095](http://192.168.200.12:30095)                       | Go 微服务 + Redis 缓存，2 副本                                 |
| webapp 应用    | [http://192.168.200.12:30096](http://192.168.200.12:30096)                       | 前端 + 后端双服务                                             |
| 应用仓库         | [http://192.168.200.12/root/podinfo.git](http://192.168.200.12/root/podinfo.git) | PAT `${GITLAB_PAT}`；分支 `main`（源码）/ `deploy`（清单） |
| OpenLDAP     | ldap://192.168.200.12:389（`dc=corp,dc=local`）                                    | `cn=admin,dc=corp,dc=local` / `${LDAP_ADMIN_PASS}`；12 个账号初始密码 `${LDAP_USER_INIT_PASS}`（应逐步改个人密码） |
| LDAP 管理界面    | [http://192.168.200.12:8090](http://192.168.200.12:8090)（phpLDAPadmin）           | `cn=admin,dc=corp,dc=local` / `${LDAP_ADMIN_PASS}`         |
| Keycloak     | [http://192.168.200.12:30087](http://192.168.200.12:30087)（realm `corp`）          | `admin` / `${KEYCLOAK_ADMIN_PASS}`                         |
| SonarQube    | [http://192.168.200.12:30091](http://192.168.200.12:30091)                        | 本地管理员 `sonaradmin` / `${SONAR_ADMIN_PASS}`；日常登录用「Log in with Keycloak」；CI 用令牌 `${SONAR_CI_TOKEN}` |
| JFrog Artifactory | [http://192.168.200.12:30092/ui/](http://192.168.200.12:30092/ui/)（备用入口 `:30100`） | `admin` / `${ARTIFACTORY_ADMIN_PASS}`；业务账号走 LDAP 直连        |
| Jenkins      | [http://192.168.200.12:30088](http://192.168.200.12:30088)                        | 统一登录走 Keycloak（`platform-admins` 组为管理员）；本地应急 `breakglass` / `${JENKINS_BREAKGLASS_PASS}` |
| Grafana      | [https://grafana.corp.local](https://grafana.corp.local)（无 NodePort）             | `admin` / `${GRAFANA_ADMIN_PASS}`（本地登录，暂未接 Keycloak）         |

> ArgoCD 官方 UI 无多语言能力，中文界面由 `30082` 上的 nginx 代理层注入词库实现，`30080` 保持原生可对照。
>
> SonarQube 的原始 `admin` 本地账号密码已不可用（早期操作后失效），已另建本地管理员 `sonaradmin` 作为应急入口；CI 流水线使用的是 `admin` 名下的用户令牌，不受影响。详见 `docs/02-流水线与交付/Sonar与Artifactory.md`。

### 统一 HTTPS 入口（2026-11-27 新增，**日常请走这里**）

入口 = `MetalLB VIP 192.168.200.210` + `ns gateway` 的 nginx 边缘网关 + 内部 CA 签发的 `*.corp.local` 通配符证书。上表的 NodePort 保留为**运维应急通道**。

| 系统 | 统一域名 | 后端 |
| --- | --- | --- |
| GitLab | `https://gitlab.corp.local` | 宿主 GitLab:80 |
| Jenkins | `https://jenkins.corp.local` | `jenkins:80`→8080 |
| Harbor | `https://harbor.corp.local` | `harbor:80`→8080 |
| SonarQube | `https://sonar.corp.local` | `sonarqube:9000` |
| Artifactory | `https://artifactory.corp.local` | `artifactory-router:8082` |
| ArgoCD | `https://argocd.corp.local` | `argocd-server:80`→8080 |
| Keycloak | `https://keycloak.corp.local` | `keycloak:80`→8080 |
| phpLDAPadmin | `https://ldapadmin.corp.local` | 宿主:8090 |
| podinfo / webapp | `https://podinfo.corp.local` / `https://webapp.corp.local` | `podinfo:80` / `frontend:80` |
| Prometheus | `https://prometheus.corp.local` | `prometheus.monitoring:9090`（Basic Auth `monitoring` / `${GATEWAY_BASIC_PASS}`） |
| Alertmanager | `https://alertmanager.corp.local` | `alertmanager.monitoring:9093`（同上） |
| Grafana | `https://grafana.corp.local` | `grafana.monitoring:3000`（Grafana 自身登录，网关不叠 Basic Auth） |

客户端先用一次 hosts + 导入 CA，详见 `docs/01-入口与网络/访问层与证书.md` 第 7 节。当前 13 个域名全部可达（`grafana` 于 2026-11-27 加入，黑盒探测 13/13 up）；`gitlab` / `keycloak` 的 302 仍指向旧 http 地址（后端 `external_url` 未切，属第二阶段，见 `docs/01-入口与网络/访问层与证书.md` 6.1）。

---

## 凭据管理（`.env`，**不入库**）

> **本仓库可以公开到 GitHub**：所有真实口令、密钥、Token、钉钉机器人地址都已从文档、清单、脚本里抽走，只留变量名。
>
> | 位置 | 写法 | 含义 |
> | --- | --- | --- |
> | 本 README / `docs/*.md` | `${HARBOR_ADMIN_PASS}` 这类 | 文档占位，真实值在 `.env` |
> | `manifests/*.yaml` | `${...}` | `apply` 前用 `envsubst` 渲染（见下） |
> | `scripts/**/*.sh` | `__HARBOR_ADMIN_PASS__` | 跑前用 `scripts/secrets/render.py`（跨平台）或 `render.sh`（Linux）渲染成临时副本 |
>
> - 真实值：`.env`（**已被 `.gitignore` 忽略**）
> - 模板：`.env.example`（上传 GitHub 的是这个，值是 `<REPLACE_ME>`）
> - **Windows 与 Linux 都能渲染**，统一用 Python 那份：
>   ```powershell
>   python scripts\secrets\render.py manifests\monitoring\51-grafana.yaml --out rendered\51.yaml
>   python scripts\secrets\render.py scripts\monitoring\705-final-verify.sh > $env:TEMP\705.sh
>   python scripts\secrets\render.py --check          # 只校验占位符，不打印真值
>   ```
>   Linux 上同样可用，shell 版 `scripts/secrets/render.sh` 保留给纯 bash 环境。
> - **`scripts/tools/ssh_exec.py` 会自动渲染**：`--script` / `--file` / 命令行参数里的 `__VAR__` 上传前就地替换，口令也从 `.env` 读，所以两边都不用先 `render.sh`。
> - 命令里要用真实值：`bash` 下 `set -a; source .env; set +a`；`PowerShell` 下 `Get-Content .env | ForEach-Object { if($_ -match '^(\w+)=(.*)'){ [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2]) } }`
> - 清单渲染（Linux 一次性）：`set -a; source .env; set +a; envsubst < manifests/monitoring/51-grafana.yaml | kubectl apply -f -`
> - 上传前自检：`git check-ignore -v .env`（应输出命中 `.gitignore`），再跑 `python scripts\secrets\render.py --check --quiet`（应无 `[missing]`），最后 `git grep --cached -n -E 'Harbor@2026|glpat-|squ_|access_token=|SECcb'`（应无结果）

## 凭据总表（2026-11-27 全量核对，**以此表为准**）

> 所有值都是 2026-11-27 从服务器现场核对过的（K8s Secret / ConfigMap / API 认证成功），不是早期文档抄下来的。
> 表里只写变量名，真实值在 `.env`；**这些是实验室环境的固定口令，上生产前必须全部轮换并改走外部密钥管理（Vault / KMS）**，但本文件本身不含明文，可以公开。

### A. 各系统管理员（本地应急账号，SSO 故障时用）

| 系统 | 入口 | 账号 | 密码 | 备注 |
| --- | --- | --- | --- | --- |
| GitLab | `https://gitlab.corp.local`（应急 `:80`） | `root` | `${GITLAB_ROOT_PASS}` | 登录页另有「Keycloak 统一登录」 |
| ArgoCD | `https://argocd.corp.local` | `admin` | `${ARGOCD_ADMIN_PASS}` | 或「Log in via Keycloak」；`argocd-initial-admin-secret` 已被改过 |
| Harbor | `https://harbor.corp.local` | `admin` | `${HARBOR_ADMIN_PASS}` | 本地应急；业务账号走 Keycloak（client `harbor`） |
| Keycloak | `https://keycloak.corp.local`（realm `corp`） | `admin` | `${KEYCLOAK_ADMIN_PASS}` | 管理控制台在 `/admin`，master realm |
| SonarQube | `https://sonar.corp.local` | `sonaradmin` | `${SONAR_ADMIN_PASS}` | 原始 `admin` 本地密码已失效，只留 CI 令牌 |
| Artifactory | `https://artifactory.corp.local`（应急 `:30092`） | `admin` | `${ARTIFACTORY_ADMIN_PASS}` | 业务账号 LDAP 直连（无 OIDC） |
| Jenkins | `https://jenkins.corp.local` | `breakglass` | `${JENKINS_BREAKGLASS_PASS}` | 本地应急管理员；日常走 Keycloak（`platform-admins` 组） |
| Grafana | `https://grafana.corp.local` | `admin` | `${GRAFANA_ADMIN_PASS}` | Secret `monitoring/grafana-admin`；暂未接 Keycloak |
| OpenLDAP | `ldap://192.168.200.12:389`（`dc=corp,dc=local`） | `cn=admin,dc=corp,dc=local` | `${LDAP_ADMIN_PASS}` | 12 个业务账号初始密码 `${LDAP_USER_INIT_PASS}`，应逐步改个人密码 |
| phpLDAPadmin | `https://ldapadmin.corp.local`（应急 `:8090`） | 同上 DN | `${LDAP_ADMIN_PASS}` | 仅网页管账号 |
| 网关 Basic Auth（Prometheus / Alertmanager） | `https://prometheus.corp.local`、`https://alertmanager.corp.local` | `monitoring` | `${GATEWAY_BASIC_PASS}` | htpasswd 在 `ns gateway` 的 `/etc/nginx/auth/htpasswd`；Grafana 刻意不加这层 |

### B. 机器 / API 凭据（CI 与自动化用，不给人登录）

| 用途 | 值 | 存在哪里 |
| --- | --- | --- |
| 宿主 SSH | `root` / `1`（`192.168.200.12:22`） | `scripts\tools\ssh_exec.py` 默认参数 |
| GitLab PAT（ArgoCD 读仓库、Jenkins 推送） | `${GITLAB_PAT}` | GitLab 变量 `GITLAB_PAT` / `GIT_PUSH_TOKEN`、K8s Secret `jenkins-casc-secrets.GITLAB_PAT` |
| Harbor 推送（GitLab CI，`apps` 项目） | `robot$apps+ci-builder` / `${HARBOR_ROBOT_CI_SECRET}` | GitLab 变量 `HARBOR_USER` / `HARBOR_PASS`（masked） |
| Harbor 推送（Jenkins，`apps` 项目） | `robot$apps+jenkins-ci` / `${HARBOR_ROBOT_JENKINS_SECRET}` | Jenkins 凭据 `harbor-jenkins-ci`，值在 Secret `jenkins-casc-secrets.HARBOR_CI_PASS` |
| Harbor 公共只读（`library` 拉基础镜像） | `robot$library+jenkins-lib-pull` / `${HARBOR_ROBOT_LIB_SECRET}` | Jenkins 凭据 `harbor-lib-pull`，值在 `HARBOR_LIB_PASS`（**审计结论：冗余，待删**） |
| Sonar 用户令牌（CI） | `${SONAR_CI_TOKEN}` | GitLab 变量 `SONAR_TOKEN`、Jenkins 凭据 `sonar-token`（同值） |
| Artifactory 发布 | `admin` / `${ARTIFACTORY_ADMIN_PASS}` | GitLab 变量 `ARTIFACTORY_USER` / `ARTIFACTORY_PASS`、Jenkins 凭据 `artifactory-admin`（OSS 版无法按仓库授权，只能留 admin） |
| Jenkins OIDC client secret（realm `corp`，client `jenkins`） | `${JENKINS_OIDC_SECRET}` | Secret `jenkins-casc-secrets.OIDC_CLIENT_SECRET`；Keycloak 侧同值 |
| 钉钉告警机器人（加签模式） | webhook `${DINGTALK_WEBHOOK_URL}` / 加签密钥 `${DINGTALK_SECRET}` | K8s Secret `monitoring/dingtalk-bot`（keys `webhook-url` / `secret`） |
| 内部 CA | `CORP Internal CA`，指纹 `E116E0323765C73653B71B57F27FDB4F2C0DDCFD`，有效期至 2036-11-24 | 宿主 `/root/gateway-tls/ca.crt`、办公机「受信任的根证书颁发机构」 |

> 单个 Secret 一次性看全（排障用）：
> `kubectl -n jenkins get secret jenkins-casc-secrets -o json | python3 -c 'import sys,json,base64;[print(k, base64.b64decode(v).decode()) for k,v in json.load(sys.stdin)["data"].items()]'`

### C. 改口令时同步动这几处（不然会静默失败）

| 改什么 | 必须同步 |
| --- | --- |
| Harbor admin 口令 | 无（CI 用 robot 账号，不用 admin） |
| Sonar 令牌 | GitLab 变量 `SONAR_TOKEN` + Jenkins 凭据 `sonar-token` + `docs/02-流水线与交付/Sonar与Artifactory.md` |
| GitLab PAT | GitLab CI 变量 `GITLAB_PAT` + Jenkins 凭据 `gitlab-pat` + ArgoCD repo 凭据 |
| Grafana admin 口令 | `kubectl -n monitoring create secret generic grafana-admin --from-literal=... --dry-run=client -o yaml \| kubectl apply -f -`，再 `rollout restart deploy/grafana`（env 从 Secret 注入，改完必须重启 Pod） |
| 网关 Basic Auth | `htpasswd -b` 改 `ns gateway` 里的 `/etc/nginx/auth/htpasswd`，再 `rollout restart deploy/gateway`（挂载在 CM/Secret 上时改源对象） |

---

## 服务全景（2026-11-27 实测盘点，含监控栈）

下面所有端口、副本、账号、存储都是当天从服务器上直接查出来的（`kubectl get`、`systemctl`、`podman ps`、各服务 API），和集群当前状态一致。

### 1. 分层全景图

```
┌────────────────────────────── 账号基座（所有人共用一套账号） ──────────────────────────────┐
│  OpenLDAP :389 (podman, dc=corp,dc=local, 12 用户 / 4 组)                                 │
│      │  只读联邦                                                         │  直连（Artifactory 无 OIDC）│
│      ▼                                                                                  ▼
│  Keycloak :30087 (realm corp，LDAP User Storage READ_ONLY，12 用户 / 4 组)      Artifactory :30092
│      │  OIDC client：gitlab / jenkins / harbor / sonarqube / argocd-dex
│      │  （phpLDAPadmin :8090 挂在 OpenLDAP 一侧，仅用于网页管账号）
└───────────────────────────────────────────────────────────────────────────────────────────┘
        │              │               │                │                 │
        ▼              ▼               ▼                ▼                 ▼
   GitLab :80     Jenkins :30088   Harbor :30090   SonarQube :30091   ArgoCD :30080/:30082
        │                                                    ▲
        │  CI（shell runner，podman）                          │ 质量门禁
        ├──────────── 1. quality-gate ────────────────────────┘
        ├──────────── 2. build → push ──────────────► Harbor
        ├──────────── 3. artifact ──────────────────► Artifactory :30092（build-artifacts 仓库）
        └──────────── 4. update-manifest ──► GitLab deploy 分支 ──► ArgoCD 同步 ──► K8s 集群
                                                                              ├─ ns podinfo（podinfo×2 + redis）
                                                                              └─ ns webapp（frontend + backend）
```

一句话概括彼此关系：

- **OpenLDAP 是唯一账号源**，Keycloak 只做"联邦 + OIDC 发牌"，业务系统不各自建号；
- **GitLab 是流水线的大脑**（源码 + `.gitlab-ci.yml` + deploy 分支），Runner 是干活的手；
- **Harbor 存镜像、Artifactory 存制品**，二者分工不重叠（镜像不进 Artifactory）；
- **Sonar 是上线前的闸门**，ArgoCD 是上线执行者，两者都只认 GitLab；
- **Jenkins 是并行的第二套 CI**：已接入 Sonar 门禁 / Harbor / Artifactory（`maven-demo-pipeline` build #7 SUCCESS），但**不写 deploy 分支**，所以不参与 ArgoCD 那条主链路。

### 2. 部署形态（谁在 K8s，谁在宿主机）

| 名称 | 部署方式 | 位置 | 副本/实例 | 说明 |
|---|---|---|---|---|
| Kubernetes | kubeadm 单节点 | 宿主机 | 1 node | `v1.32.13`，containerd `2.4.2`，Calico `v3.32.3` |
| GitLab CE 19.6.1 | **宿主机 RPM**（omnibus，runsvdir） | 宿主 `:80` | puma/nginx/gitaly/postgres/redis/sidekiq | 自带 nginx 占 80；PG/Redis 是包内的，不共用 |
| GitLab Runner 19.6.1 | **宿主机 systemd**（shell executor） | 宿主 | 1，`concurrency=1` | tag `podinfo`；直接在宿主跑 `podman`，不启容器 executor |
| OpenLDAP 1.5.0 | **podman 容器 + systemd quadlet** | 宿主 `:389` | 1 | 数据 `/data/openldap`；`openldap.service` 开机自启 |
| phpLDAPadmin 0.9.0 | **podman 容器 + systemd** | 宿主 `:8090` | 1 | `phpldapadmin.service` |
| Harbor v2.15.4 | K8s `ns harbor`（Helm） | NodePort `30090` | core/jobservice/nginx/portal/registry + db/redis Sts | PVC：registry 30Gi、db 5Gi、redis 2Gi、joblog 2Gi |
| ArgoCD v3.5.9 | K8s `ns argocd` | NodePort `30080`、`30082` | 7 个 Deployment + 1 StatefulSet | 含 dex、repo-server、redis、applicationset、notifications、中文代理层 |
| Keycloak 26.6 | K8s `ns keycloak` | NodePort `30087` | keycloak + keycloak-db | PVC `keycloak-pg` 5Gi |
| Jenkins lts-jdk21 | K8s `ns jenkins` | NodePort `30088`、`30089` | 1 | JCasC 由 ConfigMap `jenkins-casc` 驱动；PVC 10Gi |
| SonarQube 10.7-community | K8s `ns sonar` | NodePort `30091` | sonarqube + sonar-db | 插件 `sonar-auth-oidc-plugin-2.1.1.jar`；PVC 10/5/1Gi |
| JFrog Artifactory OSS 7.104.7 | K8s `ns artifactory` | NodePort `30092`、`30100` | artifactory + artifactory-db | router 8082 才是入口；PVC 20/5Gi |
| podinfo 6.17.0 | K8s `ns podinfo` | NodePort `30095` | 2 副本 + redis 1 | HPA 2→4、PDB 1、NetworkPolicy、三探针 |
| webapp（自建三层） | K8s `ns webapp` | NodePort `30096` | frontend + backend 各 1 | 与 podinfo 共用同一镜像 |
| metrics-server v0.7.2 | K8s `ns kube-system` | ClusterIP | 1 | HPA 的数据来源 |
| **MetalLB v0.14.9** | K8s `ns metallb-system` | L2 + 地址池 `192.168.200.200-215` | controller×1 + speaker×1 | 给入口分配固定 VIP `192.168.200.210` |
| **边缘网关 gateway** | K8s `ns gateway` | **VIP `192.168.200.210`:80/443** | nginx×2 | ConfigMap 驱动路由，13 个域名 + TLS + 301 + 421 |
| **监控栈** | K8s `ns monitoring` | ClusterIP（对经网关） | prometheus / alertmanager / kube-state-metrics / node-exporter(DaemonSet) / wechat-bridge / **grafana** / **blackbox-exporter** | 21 抓取目标全 up（含 13 条黑盒探测）、18 条告警规则、4 张官方看板；详见 `docs/04-可观测与告警/可观测性.md` |
| Calico / CoreDNS / etcd / apiserver / controller / scheduler / kube-proxy | K8s `ns kube-system` | — | — | 单节点控制面与 CNI |
| `ns demo`（旧 nginx 演示） | — | — | 0 | **已空**：旧演示应用下线，`:30081` 不再监听 |

### 3. 端口与入口总表

| 端口 | 服务 | 归属 | 类型 | 谁在用 |
|---|---|---|---|---|
| 22 | sshd | 宿主 | — | 运维入口（`ssh_exec.py`） |
| 80 | GitLab（内置 nginx） | 宿主 | — | GitLab Web、Git over HTTP、OIDC 回调 |
| 389 | OpenLDAP | podman | — | Keycloak、Artifactory、GitLab Runner 脚本、运维 |
| 8090 | phpLDAPadmin | podman | — | 网页管账号 |
| 6443 | kube-apiserver | 宿主 | — | kubectl、各组件 |
| 30080 / 30082 | ArgoCD 原生 / 中文代理 | `argocd` | NodePort | 部署看板、GitLab webhook 目标 |
| 30087 | Keycloak | `keycloak` | NodePort | 5 个业务系统的 OIDC |
| 30088 / 30089 | Jenkins Web / JNLP agent | `jenkins` | NodePort | Jenkins UI 与构建代理 |
| 30090 | Harbor | `harbor` | NodePort | `podman push/pull`、ArgoCD、HPA 等 |
| 30091 | SonarQube | `sonar` | NodePort | 浏览器、CI 扫描器 |
| 30092 / 30100 | Artifactory（8082 router） | `artifactory` | NodePort | CI 制品上传、运维 |
| 30095 | podinfo | `podinfo` | NodePort | 业务访问 |
| **192.168.200.210** | **统一入口（HTTP→301 / HTTPS）** | `gateway` | **MetalLB LoadBalancer** | **日常访问全部走这里（12 个 `*.corp.local` 域名）** |
| 30096 | webapp frontend | `webapp` | NodePort | 业务访问 |

> 入口层用 **MetalLB VIP + nginx 网关**，没有引入 Ingress Controller / Gateway API：单节点上装 NGF 要多 5 个 CRD 和两套控制面镜像，收益不划算（理由与取舍见 `docs/01-入口与网络/访问层与证书.md` 1.2）。NodePort 全部保留，仅作运维应急。
>
> 监控控制台（`:9090`/`:9093`）不直接暴露 NodePort，只经网关 + Basic Auth：`https://prometheus.corp.local`、`https://alertmanager.corp.local`。

### 4. 各服务职责与关键配置

#### 4.1 账号基座：OpenLDAP + Keycloak + phpLDAPadmin

- **OpenLDAP**（`dc=corp,dc=local`）：`ou=people` 12 个 `inetOrgPerson`（10 个标准 `uid=` + 2 个历史 `cn=` 条目，后者 `uid` 为 `legacy1`/`legacy2`）；`ou=groups` 用 `groupOfNames` + `member`，组为 `platform-admins`（lead01，实况还含 `legacy1`）、`devops`（ops01/ops02）、`developers`（dev01~dev05 + 2 个非标准账号）、`qa`（qa01/qa02）；另有建在 Base 下的 `cn=test` 越界组（见「已知缺口」6）。
- **Keycloak**（realm `corp`）：把 LDAP 挂成 **User Storage Provider（READ_ONLY，`editMode=READ_ONLY`）**，自己不存密码；`groups` client scope 把组写进 token。对外是 5 个 OIDC client：
  `gitlab`（回调 `/users/auth/openid_connect/callback`）、`jenkins`（`/securityRealm/finishLogin`）、`harbor`（`/c/oidc/callback`）、`sonarqube`（`/oauth2/callback/oidc`）、`argocd-dex`（`/api/dex/callback`）。
  另有 `artifactory` client（回调已建但**未启用**，因为 OSS 版不支持 OAuth）。
- **phpLDAPadmin**：加人/改密/入组的网页入口，**唯一改账号的地方**。

#### 4.2 源码与流水线：GitLab + GitLab Runner

- **GitLab**：`root/podinfo`（`main` 放源码，`deploy` 只放清单，ArgoCD 只读 deploy）、`root/cicd-demo`（早期演示仓库）；16 个用户 = 12 个 LDAP 同步账号 + `root` + `GitLabDuo`（内置）+ `lead02`/`ghost`（历史遗留）；3 个组（`developers`/`devops`/`qa`，由 `ldap-gitlab-sync.timer` 每 10 分钟维护）。
  认证：`omniauth openid_connect` → Keycloak（`ldap_enabled=false`，GitLab 不再直连 LDAP）。
- **Runner**：`podinfo-shell-podman`，shell executor，`concurrency=1`（同刻只跑一条流水线，天然避免 deploy 分支并发写冲突），tag `podinfo`，宿主上直接 `podman build/push`。
- **流水线 4 个 stage**：`quality-gate`（Sonar 扫描 + `qualitygate.wait`）→ `build-image`（构建 + 推 Harbor + registry 读回校验）→ `artifact-publish`（取二进制 → tar.gz → 传 Artifactory → sha256 读回校验）→ `update-manifest`（只改 deploy 分支 `newTag`，`resource_group: deploy-writeback`）。

#### 4.3 质量门禁：SonarQube

- 独立 PG（`sonar` 库）+ 3 个 hostPath PV；JVM 压到 web/ce 700m、search 512m；`vm.max_map_count=262144` 是硬前置。
- 登录：OIDC 插件 v2.1.1（provider key `oidc`）；本地应急 `sonaradmin`。
- 项目 `podinfo`（key 同名），默认质量门 **`cicd-gate`**：`new_reliability_rating > 3`、`new_security_rating > 3`、`new_maintainability_rating > 1` 即失败（首轮实测 `security_rating=3` 会红，把阈值收紧到 A 级就能拦住流水线）。
- 组权限：`platform-admins`/`devops` = admin，`developers`/`qa` = scan。
- CI 用令牌 `${SONAR_CI_TOKEN}`（用户 admin 名下，2026-11-25 创建）。

#### 4.4 镜像仓库：Harbor

- `auth_mode=oidc_auth`（client `harbor`，groups claim `groups`，auto onboard 开）。
- 项目：`apps`（`podinfo` 13 个 tag、`redis`、`openldap`、`metrics-server`、`busybox`）、`library`（`sonarqube`、`artifactory-oss`、`sonar-scanner-cli`、`postgres`、`keycloak`、`jenkins`）。
- **全部自建服务镜像都从这里拉**（K8s 里 10 个业务镜像有 8 个来自 `192.168.200.12:30090`），但 Harbor 自身组件仍用 `docker.io/goharbor/*`。
- 角色：CI 的"镜像门禁"依据 `GET /v2/<repo>/manifests/<tag>` 是否 200 判断，读不到就不写部署清单。

#### 4.5 制品仓库：JFrog Artifactory（OSS）

- 仓库 `build-artifacts`（Local / Generic），路径规范 `podinfo/<分支>/<commit-sha>/podinfo-<sha>.tar.gz(+ .sha256)`。
- 账号：本地 `admin`（内部密码登录已恢复）+ LDAP `corp-ldap`（`member` 属性，`STATIC` 组映射）。
- **明确不做**：镜像存储（归 Harbor）、REST 建仓（Pro 限定）、OAuth/SAML（OSS 不含）。
- 只有 CI 的 `artifact-publish` 会写它，ArgoCD/Harbor 都不读它。

#### 4.6 部署编排：ArgoCD

- 两个 Application，都指向 `root/podinfo` 的 **`deploy` 分支**：`podinfo → deploy/podinfo`、`webapp → deploy/webapp`，均 `Synced / Healthy`。
- 认证：`argocd-dex` client → Dex（`connectors: oidc keycloak`，`insecureEnableGroups`）→ Keycloak；RBAC `platform-admins`/`devops`=admin、`developers`/`qa`=readonly。
- 中文界面由 `argocd-zh-proxy`（nginx 注词库）在 `:30082` 提供。
- GitLab 侧配了 webhook 指向 ArgoCD `/api/webhook`，push deploy 分支即触发同步（轮询兜底仍在）。

#### 4.7 第二套 CI：Jenkins

- JCasC 驱动：`oicSecurityRealm`（client `jenkins`，scopes 含 `groups`，`groupsFieldName: groups`）+ `globalMatrix`（`Overall/Administer:platform-admins`）；`numExecutors: 2`。
- 有 LDAP 账号即可登录。**已有一条完整流水线**：`maven-demo-pipeline`（`root/demo-maven`，5 stage：拉代码 → Sonar + 门禁 → Maven 打包 → Jib 推 Harbor → jar/sha256/build-info 推 Artifactory），build #7 SUCCESS、34.7 s，凭据全部来自 K8s Secret `jenkins-casc-secrets`。**它不写 deploy 分支**，因此与 GitLab→ArgoCD 主链路互不干扰；详见 `docs/02-流水线与交付/Jenkins流水线.md`。

#### 4.8 业务负载

- `ns podinfo`：`podinfo` 2 副本（`readonlyRootFilesystem`、drop ALL、三探针、HPA 2→4、PDB 1、NetworkPolicy）+ `redis:7-alpine`；镜像 `apps/podinfo:<commit-sha>`。
- `ns webapp`：`frontend` + `backend`，共用同一个 podinfo 镜像（`--backend-url` 指向 backend 的 `/echo`）；NodePort `30096`。

#### 4.9 K8s 基础组件

`kube-system`：`etcd` / `kube-apiserver` / `kube-controller-manager` / `kube-scheduler`（单节点静态 Pod）、`kube-proxy`、`calico-node`+`calico-kube-controllers`（Pod 网络）、`coredns`×2（集群 DNS）、`metrics-server`（HPA 指标）。没有 StorageClass，全部用 hostPath + 手工 PV/PVC（`local-sonar-*`、`local-arti-*` 等）。

### 5. 三条真实链路（含端口与认证方式）

**A. 发版链路（改动代码 → Pod 换新）**

1. 开发者 `git push` 到 `root/podinfo` 的 `main`；
2. GitLab 触发流水线（Runner 在宿主跑 podman，`concurrency=1`）；
3. `quality-gate`：scanner 容器扫源码 → `:30091`（`SONAR_TOKEN` 认证）→ `sonar.qualitygate.wait=true` 等 `cicd-gate` 结果，**ERROR 则整条停**；
4. `build-image`：`podman build -f Dockerfile.ci` → `podman login` :30090（robot 或 admin）→ push `apps/podinfo:<sha>` → `ci/verify-image.sh` 读 registry manifest 必须 200；
5. `artifact-publish`：`podman cp` 出 `/home/app/podinfo`、`/usr/local/bin/podcli` → tar.gz + sha256 → 上传 `:30092/artifactory/build-artifacts/...` → 读回比对 sha256；
6. `update-manifest`：以远端 `deploy` 为基重建提交，`sed` 两处 `newTag`，push 到 `deploy`（`resource_group` 保证同一时刻只有一个写入者）；
7. ArgoCD 通过 webhook / 轮询发现 `deploy` 变化 → 同步 `podinfo`、`webapp` 两个 Application → 从 `:30090` 拉新镜像（`imagePullSecret`）；
8. 滚动更新完成（实测提交到新 Pod 就绪约 2 分钟）。

**A2. Jenkins 发版链路（并行的第二条，止于推 JFrog）**

1. Jenkins Job `maven-demo-pipeline`（`http://192.168.200.12:30088`）拉 `root/demo-maven` 的 `main`；
2. `platform-lib` 共享库执行：Sonar 扫描 + `cicd-gate` 门禁判定（ERROR 即停）→ Maven 打包；
3. Jib 直接推 `apps/maven-demo:1.0.<构建号>` 到 Harbor（无 docker daemon）；
4. jar + `.sha256` + `build-info.json` 推 `build-artifacts/maven-demo/main/1.0.<N>/` 并回读校验；
5. 实测 build #6 全程 27 s，SUCCESS；**尚未接入 ArgoCD 自动部署**。详见 `docs/02-流水线与交付/Jenkins流水线.md`。

**B. 登录链路（一套账号进 5 个系统）**

```
浏览器 → 各系统登录页点「Keycloak / 统一登录」
       → Keycloak :30087/realms/corp（校验密码时回源 LDAP :389，READ_ONLY）
       → 回调各系统（回调地址见 4.1）
       → token 里带 groups → 各系统按组授权
```
Artifactory 是例外：不走 Keycloak，UI 里直接 LDAP bind（同一批账号）。

**C. 加人链路（只改一处）**

1. 在 phpLDAPadmin（`:8090`）或 `scripts/ldap/ldap-add-user.sh` 建用户并放进组；
2. `ldap-gitlab-sync.timer`（每 10 分钟）把 LDAP 组同步成 GitLab 组/成员，并清退已移出组的人；
3. Keycloak 的 LDAP 联邦自动看到新用户，下次登录即生效；
4. Artifactory 下次 LDAP bind 也直接认得（无需建号）。

### 6. 依赖矩阵与故障影响面

| 服务 | 依赖 | 它挂了会怎样 |
|---|---|---|
| OpenLDAP | 无（podman 自管） | **全站登录失效**（Keycloak、Artifactory 都回源它）；已登录会话短期内仍可用 |
| Keycloak | OpenLDAP + `keycloak-db` | 5 个系统的"统一登录"不可用；本地应急账号（GitLab root、Harbor admin、ArgoCD admin、Sonar sonaradmin、Artifactory admin）仍能进 |
| GitLab | 自身 PG/Redis/Gitaly（包内） | 无法提交/触发流水线/写 deploy；ArgoCD 仍按现有 deploy 状态运行 |
| GitLab Runner | GitLab + podman | 流水线排队不动，镜像/制品不更新（集群保持现状） |
| Harbor | `harbor-db`/`harbor-redis`/PV | 推拉镜像全失败；已在节点上的镜像仍可运行（`imagePullPolicy` 若为 Always 会受影响） |
| SonarQube | `sonar-db` + ES 数据盘 + 宿主 sysctl | `quality-gate` 失败 → **流水线阻断**（这是设计上的"宁可不上线"） |
| Artifactory | `artifactory-db` + `/data/artifactory` | `artifact-publish` 失败 → 流水线停在 artifact 阶段，不写 deploy，旧版本继续跑 |
| ArgoCD | GitLab（读 deploy）+ Harbor（拉镜像） | 新提交不再自动上线；手动 `kubectl apply` 仍可 |
| Jenkins | Keycloak（登录）+ 自身 PVC | 只影响 Jenkins 自身，主链路无感 |
| metrics-server | kubelet | HPA 失效，副本不再自动伸缩（不影响发布） |

一句话：**LDAP/Keycloak 是"人"的单点，Harbor 是"镜像"的单点，GitLab 是"变更"的单点**；Sonar 与 Artifactory 失败只会"卡住上线"，不会破坏已运行的服务——这正是把它们放在 build 之前/之后的原因。

### 7. 存储与容量现状

| 位置 | 用途 | 容量 |
|---|---|---|
| `/data/harbor` | registry / db / redis / joblog | 4.0G |
| `/data/sonarqube/{pg,data,plugins}` | Sonar PG + ES + 插件 | 403M |
| `/data/jenkins` | Jenkins home（PVC 10Gi） | 304M |
| `/data/artifactory/{pg,data}` | Artifactory PG + 制品（20Gi/5Gi） | 109M |
| `/data/keycloak` | Keycloak PG（5Gi） | 69M |
| `/data/openldap` | LDAP 数据 | 296K |

宿主资源：8C/22G，根盘 64G（已用 52G，剩约 12G，82%）；内存已用 14Gi / 可用 1Gi（另有 7Gi buff/cache）。当前最吃内存的是 `artifactory`（约 2.4Gi，limit 4Gi）与 `kube-apiserver`（约 640Mi）。

### 8. 已知缺口与不一致（盘点时如实记录）

1. **`ns demo` 已空**：旧 nginx 演示应用与 `:30081` 已下线，README 里不要再当活服务引用。
2. **Sonar 原始 `admin` 本地密码失效**：现用 `sonaradmin` 应急；`admin` 只以 CI 令牌形式在流水线里生效，改动前先读 `docs/02-流水线与交付/Sonar与Artifactory.md` 的凭据表。
3. **Sonar 强制登录**（`sonar.forceAuthentication=true`）：匿名 API 一律 401，脚本必须带令牌或本地管理员。
4. **Artifactory LDAP 组未做权限映射，且 OSS 版根本无法做**：`platform-admins/devops/developers/qa` 还没在 Artifactory 里建组/挂 permission target；进一步实测发现 OSS 把 `/api/security/users`、`/api/security/permissions` 全部锁成 400 `available only in Artifactory Pro`，非 admin 的 LDAP 账号（如 `dev01`）读 200、写 **403**。也就是说 OSS 上**无法**建"只能上传某仓库"的专用账号，只能继续用 `admin`（口令已挪进 K8s Secret `jenkins-casc-secrets`）或升级 Pro。
5. **Jenkins 已接入 Sonar/Artifactory，但止于"推 JFrog"**：`maven-demo-pipeline`（build #6 SUCCESS）已跑通 拉代码→Sonar 门禁→Maven 打包→Jib 推 Harbor→jar+sha256+build-info 推 Artifactory，**未自动部署到集群**；Jenkins 仍缺 `timestamper/junit/ws-cleanup/maven-plugin` 四个插件，靠 workaround 代替。详见 `docs/02-流水线与交付/Jenkins流水线.md`。
6. **LDAP 目录有越权遗留（2026-11-26 实测）**：`cn=遗留账号1,ou=people`（uid `legacy1`，uidNumber 1000）同时属于 `platform-admins` 与 `developers`，另有一个建在 Base 下的 `cn=test` 组；该账号经 Keycloak 会同时拿到 GitLab/Harbor/Jenkins/Sonar/ArgoCD 的管理员权限。另一个 `cn=legacy2`（uid `legacy2`）DN 含空格。**建议优先清理**，步骤见 `docs/03-身份与账号/OpenLDAP目录.md` 2.3。
7. **单节点全栈**：控制面、Harbor、GitLab、Keycloak 均为单实例，没有高可用；Keycloak 一挂六个系统都无法新登录。`/` 只剩 19G，再拉大镜像（如新版本 Sonar/Artifactory）前要先 `podman image prune` 或扩盘。
8. **无 StorageClass；入口层已补，尚无 Ingress/Gateway API**：PV 全是 hostPath 手工建，节点迁移需要同步 `/data`；对外入口已收敛为 MetalLB VIP + nginx 网关（`docs/01-入口与网络/访问层与证书.md`），但**没有** Ingress 资源抽象，路由改在 `manifests\gateway\20-nginx-config.yaml`，改完必须 `rollout restart`。
9. **GitLab 已关 LDAP 直连**（`ldap_enabled=false`），只保留 OIDC；Keycloak 挂了 LDAP 用户无法登录 GitLab，只能用 `root` 本地账号。
10. **TLS 只做到入口层**：客户端到 VIP 是 https（内部 CA，需导 `ca.crt`），但**后端各系统仍按 http 生成绝对 URL** —— `gitlab.corp.local` 与 `keycloak.corp.local` 的 302 会指向旧 http 地址；各服务 `external_url` / `KC_HOSTNAME` / OIDC 回调要一次性切换（清单见 `docs/01-入口与网络/访问层与证书.md` 6.1）。LDAP 仍是 389 明文。`/data` 六个目录没有定期备份或恢复演练（最该补的一项，仍未做）。
11. **可观测已到"指标 + 看板 + 探测"，缺日志与业务指标**：Prometheus / ksm / node-exporter / Alertmanager / **Grafana（4 张官方看板）/ blackbox-exporter** 均已上线（21 目标全 up，含 13 条入口黑盒探测，告警到企业微信桥接已实测）；仍缺 **Loki 日志、Harbor/Jenkins/Sonar 业务指标（需装 exporter 或插件）以及 Grafana 接 Keycloak OIDC**（能力边界见 `docs/04-可观测与告警/可观测性.md` 第 3、11 节）；钉钉群已接通并实测（加签模式，触发/恢复各收到一条，`errcode:0`；路由默认 `dingtalk-ops`），企业微信与 SMTP 仍是占位；规则集 18 条见 `docs/04-可观测与告警/告警接入.md`。
12. **CI 收敛只做了一半**：方案 A 已确立（Jenkins 仅独立任务、不写 `deploy`，任务描述已标注），凭据已全量审计，但 **4 项最小权限动作待执行**（`GIT_PUSH_TOKEN` 加 Protected、`gitlab-pat` 换 Deploy Token、删冗余 `harbor-lib-pull`、拆分 auth/ci 两个 Secret），清单见 `docs/02-流水线与交付/CI凭据治理.md` 第 4 节。

## 部署的应用

**podinfo**（[stefanprodan/podinfo](https://github.com/stefanprodan/podinfo) 6.17.0，Go + gRPC + Web UI）：



* 2 副本滚动更新（`maxUnavailable: 0`）、readonly rootfs、drop ALL capabilities、三探针

* 依赖 Redis 缓存（`PODINFO_CACHE_SERVER=tcp://redis:6379`）

* HPA 2→4（CPU 70%）、PDB minAvailable 1、双向 NetworkPolicy

* NodePort 30095

**webapp**（上游 `deploy/webapp` 三层清单改造）：



* backend + frontend 两个 Deployment、两套 HPA、独立 ServiceAccount 与 RBAC

* frontend 通过 `--backend-url` 调 backend 的 `/echo`

* NodePort 30096

两套应用共用同一个 Harbor 镜像，CI 一次构建同时回写两处 `newTag`。

## 组件版本



| 组件             | 版本                                                     |
| -------------- | ------------------------------------------------------ |
| 操作系统 / 硬件 | Rocky Linux 10.2，8C/22G，内核 6.12，单机 |
| Kubernetes     | v1.32.13（kubeadm 单节点，containerd v2.4.2，Calico v3.32.3，CoreDNS v1.11.3） |
| GitLab CE      | 19.6.1（Omnibus RPM，宿主 :80）                          |
| GitLab Runner  | 19.6.1（shell executor + podman，`concurrency=1`）        |
| Harbor         | v2.15.4（Helm 部署，NodePort 30090，hostPath 静态 PV）         |
| ArgoCD         | v3.5.9（含 Dex v2.45.1，中文代理 :30082）                  |
| Keycloak       | 26.6（realm `corp`，LDAP 联邦 READ_ONLY）                  |
| OpenLDAP       | osixia/openldap 1.5.0（podman，:389）                     |
| phpLDAPadmin   | 0.9.0（podman，:8090）                                    |
| Jenkins        | lts-jdk21（JCasC，NodePort 30088/30089）                  |
| SonarQube      | 10.7-community + sonar-auth-oidc-plugin 2.1.1（NodePort 30091） |
| JFrog Artifactory | OSS 7.104.7（NodePort 30092/30100）                    |
| PostgreSQL     | 16（Keycloak / Sonar / Artifactory / Harbor 各自独立实例）  |
| metrics-server | v0.7.2（HPA 数据源）                                        |
| podinfo        | 6.17.0                                                 |

## 文件导航



* **CI/CD 链路详解**：`docs/02-流水线与交付/CI-CD流水线.md`（Harbor/Runner/ 流水线 / 清单 / 踩坑 / 验证）

* **LDAP 统一账号与权限**：`docs/03-身份与账号/OpenLDAP目录.md`（目录结构、4 组 12 账号（含 2 个 `cn=` 历史条目）、组继承、各系统权限矩阵、`cn=test` 越界组待清理）

* **新增 LDAP 用户操作手册**：`docs/03-身份与账号/LDAP新增用户手册.md`（网页/命令建号、入组、验证、常见坑、离职删号、现网遗留条目）

* **环境部署文档**：`docs/02-流水线与交付/部署与回滚.md`（K8s、GitLab、ArgoCD 分步部署与排障；已补当前组件拓扑与容量（含监控栈））

* **GitOps 流水线方案**：`docs/02-流水线与交付/GitOps与ArgoCD.md`（main/deploy 分支模型、四道门禁、并发保护、回滚与验证记录）

* **Jenkins**：`docs/02-流水线与交付/Jenkins部署.md`（http://192.168.200.12:30088，Keycloak OIDC 登录、globalMatrix 权限、部署与排障、接 Sonar/Artifactory 方案）

* **Jenkins Pipeline + 共享库**：`docs/02-流水线与交付/Jenkins流水线.md`（5 stage 流水线（拉代码→Sonar→打包→Jib 推 Harbor→推 JFrog）、`platform-lib` 共享库设计、从零搭建命令、六次构建排障表、验证清单与已知限制）

* **制品归档与拉取**：`docs/02-流水线与交付/镜像与制品拉取.md`（Jenkins 归档 / Artifactory / Harbor 三处归档位置对照、各场景拉取命令、校验方法、拉不到时的对照表）

* **生产化方案**：`docs/01-入口与网络/生产架构与改造路线.md`（现状分层判定、组件结合的 5 条原则、CI 收敛取舍、改造矩阵与 P0~P3 路线、不建议做的事；文末已补「执行记录」）

* **统一访问层（MetalLB + TLS + 网关）**：`docs/01-入口与网络/访问层与证书.md`（为什么不用 NGF、VIP/证书/域名清单、部署步骤、5 条踩坑、遗留 external URL 切换清单、客户端接入、Runbook）

* **可观测（Prometheus + 告警）**：`docs/04-可观测与告警/可观测性.md`（组件与抓取矩阵、能抓/抓不到的能力边界、18 条告警规则、Grafana 看板与黑盒探测、企业微信必须过 bridge 的原因与接法、4 条踩坑、验证命令、下一步）

* **CI 收敛与凭据治理**：`docs/02-流水线与交付/CI凭据治理.md`（方案 A 定义、两条链路现状、GitLab 7 变量 / K8s Secret 8 键 / Jenkins 5 凭据全量审计、4 项待收敛动作、轮换 SOP）

* **测试报告**：`docs/05-组件与测试/验收测试用例.md`（链路用例与实测时序；第 9 节为 4 stage/SSO/制品的新增用例）

* **SonarQube + JFrog Artifactory**：`docs/02-流水线与交付/Sonar与Artifactory.md`（部署、OIDC/LDAP 接入、质量门 `cicd-gate`、制品上传与校验、CI 四 stage 接法、故障速查）

* **统一登录**：`docs/03-身份与账号/统一身份SSO-Keycloak.md`（Keycloak realm/LDAP 联邦/OIDC client，逐服务对接与回滚）

* **清单**：`manifests\podinfo\`（Dockerfile.ci、.gitlab-ci.yml、kustomization、app、redis、ArgoCD Application）、`manifests\webapp\`、`manifests\infra\metrics-server.yaml`

* **脚本目录（按组件分组，已精简）**：`scripts\README.md` — `tools\`、`k8s\`、`argocd\`、`gitlab\`、`harbor\`、`runner\`、`pipeline\`、`app\`、`ldap\`、`jenkins\`、`keycloak\`、`sonar-jfrog\`、`gateway\`、`monitoring\`、`ci\`、`verify\`、`probe\`；共 220 个脚本（本轮新增 `gateway\400~433` 23 个、`monitoring\500~525` 11 个、`ci\600~601` 2 个、`verify\960` 1 个），一次性排错脚本已打包到 `_archive\scripts-full-backup-20261126.zip`

* **新增 LDAP 用户**：`scripts\ldap\ldap-add-user.sh`（一条命令完成建条目、入组、立即同步，已实测）
* **新增 LDAP 权限组 / 分区 OU**：`scripts\ldap\ldap-add-group.sh`、`scripts\ldap\ldap-add-ou.sh`（均装到服务器 `/usr/local/bin/`）
* **LDAP→GitLab 组同步**：`scripts\ldap\ldap-gitlab-sync.sh`（服务器侧 `/usr/local/bin/`，systemd timer 每 10 分钟执行）

* **SSH 执行器**：`scripts\tools\ssh_exec.py`（`--script` 跑整段脚本、`--put` 上传文件）

### 文档时效对照（2026-11-26 全部文档已按现状更新）

> 2026-11-27：`docs/` 已按 5 类重组（`01-入口与网络` / `02-流水线与交付` / `03-身份与账号` / `04-可观测与告警` / `05-组件与测试`，全中文命名），跨文档引用已统一到新路径。**完整索引与 30 分钟阅读顺序见 `docs/README.md`**，下表只保留覆盖面与时效。

| 文档 | 覆盖范围 | 状态 |
|---|---|---|
| `README.md`（本文件） | **当前全部组件、端口、账号、链路、容量** | 最新（2026-11-26 实测盘点） |
| `docs/05-组件与测试/组件清单.md` | **七套系统的定位、核心概念、配置、排查边界、一次提交走过的链路** | 新增（2026-11-26，按数据流顺序） |
| `docs/02-流水线与交付/Sonar与Artifactory.md` | Sonar + Artifactory 部署、接入、CI 四 stage、验证与排障 | 最新；命令中的 Sonar 凭据已统一为 `sonaradmin` |
| `docs/03-身份与账号/统一身份SSO-Keycloak.md` | Keycloak realm/LDAP 联邦/OIDC client、逐服务对接、回滚、风险 | 最新；7.5 已用 `sonaradmin`，第 13 节风险清单按现状重写 |
| `docs/03-身份与账号/OpenLDAP目录.md` | 目录结构、组继承、账号实况（12=10+2 非标准）、各系统权限矩阵 | 最新；直连配置已标注为历史，ArgoCD 章节已改 Dex→Keycloak OIDC |
| `docs/03-身份与账号/LDAP新增用户手册.md` | 建号 → 入组 → 同步 → 验证 → 离职 | 最新；补「`uid` DN 规范」「现网遗留条目清理」两节 |
| `docs/02-流水线与交付/CI-CD流水线.md` | Harbor + Runner + **4 stage 流水线**、清单、踩坑、验证 | **已重写为当前形态**（第 4/6/8 节全换） |
| `docs/02-流水线与交付/GitOps与ArgoCD.md` | main/deploy 分支模型、四道门禁、并发保护、回滚 | 已更新（架构图与门禁清单含 quality/artifact，补 #27 验证记录） |
| `docs/02-流水线与交付/部署与回滚.md` | 单节点部署全流程 + 当前组件拓扑/版本/容量（含监控栈） | 已更新（第 1/2/7/8/9 节） |
| `docs/02-流水线与交付/Jenkins部署.md` | Jenkins 部署、JCasC(OIDC)、权限矩阵、接 Sonar/Artifactory 方案 | 已更新（认证、清单、权限矩阵、第 8 节新方案） |
| `docs/02-流水线与交付/Jenkins流水线.md` | **Jenkins Pipeline + 共享库**：5 stage、设计取舍、从零搭建、六次构建排障、验证与限制 | 新增（2026-11-26，build #6 SUCCESS 实测） |
| `docs/02-流水线与交付/镜像与制品拉取.md` | 制品归档后怎么拉：Jenkins Archive / Artifactory / Harbor 三处入口、命令模板、校验、失败对照 | 新增（2026-11-27，按 build #6/#7 实测写） |
| `docs/01-入口与网络/生产架构与改造路线.md` | 组件怎么结合才像生产：现状判定、5 条组合原则、CI 收敛取舍、P0~P3 改造路线 + **执行记录** | 2026-11-27 方案 + 11-27 施工记录（入口层/可观测/CI 标注已完成） |
| `docs/01-入口与网络/访问层与证书.md` | **统一访问层**：MetalLB VIP、内部 CA + 通配符证书、nginx 网关、13 域名路由（含 grafana）、踩坑、遗留 external URL 切换 | 新增（2026-11-27，全部实测） |
| `docs/04-可观测与告警/告警接入.md` | **告警接入**：链路四跳、18 条规则总表、分组与抑制、钉钉加签接入 4 步、验收与 errcode 排障 | 新增（2026-11-27） |
| `docs/04-可观测与告警/可观测性.md` | **可观测**：Prometheus/ksm/node-exporter/Alertmanager/企业微信桥接 + **Grafana 四张官方看板 + blackbox 黑盒探测**、抓取矩阵、告警规则、验证与排障 | 2026-11-27 更新（21 目标 up + 看板/探测实测） |
| `docs/02-流水线与交付/CI凭据治理.md` | **CI 收敛方案 A + 凭据治理**：两条链路定位、三处凭据全量审计、4 项待收敛、轮换 SOP | 新增（2026-11-27） |
| `docs/05-组件与测试/验收测试用例.md` | 链路用例与实测时序 | 已更新（v1 标注 + 第 9 节 9 条新用例 TC-33~41） |
| `scripts\README.md` | 脚本索引与执行方式 | 已更新（本轮新增 gateway/monitoring/ci 三组，共 220；目录/文件数按实计） |

> 维护规则：新增/停用任何组件时，**先改 README「服务全景」，再同步对应 docs 正文**（不是只加时效横幅）；改完顺手核对本表。

## 快速验证



```
cd C:\Users\morning\Desktop\cicd

# 环境总览
python scripts\tools\ssh_exec.py "kubectl -n argocd get applications; kubectl -n podinfo get pods; kubectl -n webapp get pods"

# 服务可用性
python scripts\tools\ssh_exec.py "curl -s http://192.168.200.12:30095/version; curl -s -X POST -d '{}' http://192.168.200.12:30096/echo"

# 一次完整发版验证（4 stage 全绿 + ArgoCD 上线）
python scripts\tools\ssh_exec.py --script scripts\pipeline\103-e2e2.sh --timeout 600

# LDAP 目录现状（12 账号 / 4 组 / 非标准条目）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1120-ldap-dump.sh --timeout 90

# 各系统账号与角色（GitLab 用户数、Harbor 项目成员）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1123-users-check.sh --timeout 60

# Sonar / Artifactory 与四 stage 流水线（门禁 + 制品 + ArgoCD 镜像 tag）
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1010-final-verify.sh --timeout 60

# 统一入口回归（13 域名状态 + 证书链 + 301 + 421）
python scripts\tools\ssh_exec.py --script scripts\gateway\422-verify-routes.sh --timeout 180

# 可观测回归（21 抓取目标 + 18 条规则 + 13 条黑盒探测 + Grafana 看板 + 控制台 Basic Auth + 钉钉桥自测）
python scripts\tools\ssh_exec.py --script scripts\monitoring\521-verify.sh --timeout 300

# CI 凭据审计（GitLab 变量 vs K8s Secret vs Jenkins 凭据）
python scripts\tools\ssh_exec.py --script scripts\ci\600-audit-credentials.sh --timeout 200
```

## 统一账号（LDAP → Keycloak）

OpenLDAP 是唯一账号源；业务系统通过 **Keycloak OIDC** 登录（GitLab `openid_connect`、Jenkins `oicSecurityAuth`、Harbor `oidc_auth`、ArgoCD 经 Dex 的 `oidc` connector、Sonar `authoidc`），**Artifactory 是唯一 LDAP 直连**（OSS 无 OIDC）。GitLab 的 `ldap_enabled` 已关闭。

| 账号             | 组               | Harbor（`apps` 项目） | GitLab（`root/podinfo`） | ArgoCD | Sonar（组） | Artifactory |
| -------------- | --------------- | ----------------- | ---------------------- | ------ | -------- | ---------- |
| lead01         | platform-admins | 系统管理员             | 实例管理员 + maintainer     | admin | admin | LDAP 可登录 |
| ops01 / ops02  | devops          | maintainer        | maintainer             | admin | admin | LDAP 可登录 |
| dev01 ~ dev05  | developers      | developer         | developer              | readonly | scan | LDAP 可登录 |
| qa01 / qa02    | qa              | guest             | reporter               | readonly | scan | LDAP 可登录 |

GitLab 登录：**点登录页的「Keycloak 统一登录」**（`Corp LDAP` 标签页已停用，Standard 通道对 LDAP 用户无效）。新人只在 LDAP（或 http://192.168.200.12:8090）加账号并放进组即可：`ldap-gitlab-sync.timer` 每 10 分钟自动在 GitLab 建号、按组赋权、清退已移出组的人；Keycloak 侧下一次登录自动可见。**逐步操作见 `docs/03-身份与账号/LDAP新增用户手册.md`**，机制与踩坑见 `docs/03-身份与账号/OpenLDAP目录.md`。

ArgoCD 点登录页 **LOG IN VIA DEX**（用户名填 `uid`），组变了重新登录即生效；本地 `admin` 保留作超级用户。Sonar 点 **「Log in with Keycloak」**，组同步（`groups` claim）决定 admin/scan 权限。

新建**权限组**或**分区（OU）**：网页模板 `Corp: Permission Group` / `Generic: Organisational Unit`，或 `ldap-add-group.sh <组名> <说明> <首个成员>`、`ldap-add-ou.sh <ou名>`。新组默认零权限，需在 GitLab `GMAP`、Harbor 项目成员、ArgoCD `policy.csv`、Sonar 组授权四处登记（Artifactory 侧暂未映射组，见「已知缺口」）。

## 发版与回滚



```
# 发版：只需 push 到 main（清单由 CI 写 deploy 分支，main 不再被回写）
cd /root/podinfo-src && git pull && git commit -am "feat: xxx" && git push origin main

# 回滚：在 deploy 分支改 tag 或 revert 一条部署提交（不触发构建，秒级）
git clone http://192.168.200.12/root/podinfo.git && cd podinfo && git checkout deploy
git revert <deploy 提交> --no-edit && git push origin deploy
```

> 完整设计（分支模型、三道门禁、验证记录、排障）见 `docs/02-流水线与交付/GitOps与ArgoCD.md`。要点：`main` 只放源码；`deploy` 分支只放 `deploy/` 清单，ArgoCD 只读它；构建完先校验 registry 里 tag 可读，再写清单；main 已前进时旧流水线主动跳过写回。

## 注意事项



1. 服务器**不能直连 Docker Hub / GitHub**。镜像走 `docker.m.daocloud.io`（docker.io）、`m.daocloud.io`（registry.k8s.io）；GitHub 代码走 `gh-proxy.com` 前缀代理。

2. containerd 2.x 的仓库配置必须写在 `[plugins.'io.containerd.cri.v1.images'.registry] config_path = '/etc/containerd/certs.d'`，旧写法不生效。

3. Harbor 项目 `apps` 是私有的，集群里每个命名空间都需要一份 `harbor-regcred`（`podinfo`、`webapp`、`kube-system` 三处已建）。

4. Windows 侧 `ssh_exec.py` 传命令时避免 `$()`——PowerShell 会先行展开，复杂命令请写成 `.sh` 用 `--script` 执行。

5. 内存已扩到 16 GB（此前记录 7 GB 已过期）；K8s 节点 capacity 需要 `systemctl restart kubelet` 才会刷新。

6. LDAP 组权限依赖 OpenLDAP 的 `memberof` overlay（Harbor 读 `memberOf` 属性）；改组成员后用户**重新登录**才会刷新组映射。GitLab CE 无 LDAP 组同步，组权限需 API 手工赋权。

7. LDAP 当前仅开放 389 明文端口，未配 TLS；生产化需补 LDAPS/StartTLS。