# CI/CD 逻辑与网络流量走向（现网实测版）

> 事实基准：2026-11-27 现场采集（`scripts/gateway/543-flow-inventory.sh`）。
> 适用：单节点 K8s（`192.168.200.12`，Rocky Linux 10.2）+ MetalLB VIP `192.168.200.210` + 自建内部 CA。
> 本文只描述"现在真实怎么走"，历史形态与踩坑见 `docs/01-入口与网络/访问层与证书.md` 5.x / `docs/03-身份与账号/统一身份SSO-Keycloak.md` §9.5–9.6。

---

## 1. 一句话总览

```
开发者 git push ──► GitLab(宿主 systemd, :80) ──► GitLab Runner(宿主 shell executor)
                                                   │  git clone https://gitlab.corp.local
                                                   │  podman build / scan / push https://harbor.corp.local
                                                   ▼
                                        deploy 分支（只放清单，唯一写入者=GitLab CI）
                                                   │  webhook + 每 3 分钟轮询
                                                   ▼
                              ArgoCD（ns argocd）──► kubectl apply ──► kubelet/containerd 拉镜像
                                                                       （清单写域名或旧 IP 名，两条路都通）
```

**边界很清晰**：

- **只有 GitLab CI 能写 `deploy` 分支**（Jenkins 只做独立的构建/门禁/制品任务，没有任何可写 deploy 的凭据）。
- **所有人工访问只走 `https://*.corp.local`（VIP .210:443）**，NodePort 只用于 Pod 内部/排障直连。
- **镜像仓库的规范地址是 `https://harbor.corp.local`**，`192.168.200.12:30090` 靠 containerd 别名映射过去，仅老清单在用。

---

## 2. 地址矩阵（现网）

### 2.1 入口层（浏览器/客户端）

| 域名（`*.corp.local`） | 解析到 | 网关转发到（ClusterIP:Port） | 备注 |
|---|---|---|---|
| gitlab | 192.168.200.210 | 宿主 `192.168.200.12:80`（GitLab RPM，非 Pod） | 走 gateway 的 `set $backend` 直连宿主 IP |
| keycloak | .210 | `10.102.197.7:80` | KC_HOSTNAME=https |
| harbor | .210 | `10.107.110.95:80`（harbor nginx） | 同一个后端也承载 `/v2/` registry |
| sonar | .210 | `10.96.49.186:9000` | |
| artifactory | .210 | `10.109.31.47:8082` | |
| jenkins | .210 | `10.96.84.76:80` | 网关侧 Basic Auth 保护 |
| argocd | .210 | `10.101.14.25:80` | |
| ldapadmin | .210 | 宿主 `192.168.200.12:8090` | phpLDAPadmin |
| podinfo / webapp | .210 | `10.108.211.77:80` / `10.99.219.124:80` | 业务演示 |
| prometheus / alertmanager | .210 | `10.98.134.245:9090` / `10.103.87.112:9093` | 网关 Basic Auth（`monitoring/${GATEWAY_BASIC_PASS}`） |
| grafana | .210 | `10.106.157.157:3000` | Grafana 自身登录（admin），网关不叠 Basic Auth |

网关自身：Service `gateway`（LoadBalancer，`10.108.229.246`，VIP `192.168.200.210`，端口 80/443，NodePort 31843/32636）。证书 `gateway-tls`，SAN 覆盖 `*.corp.local` + IP `.210/.12`。

### 2.2 集群内关键 Service（排障必查）

| 命名空间 | Service | ClusterIP | 端口 |
|---|---|---|---|
| argocd | argocd-server | 10.101.14.25 | 80,443 |
| argocd | argocd-repo-server | 10.98.143.135 | 8081,8084 |
| argocd | argocd-dex-server | 10.99.48.246 | 5556 |
| harbor | harbor（nginx/portal/registry 统一入口） | 10.107.110.95 | 80 |
| harbor | harbor-core / registry / jobservice / database / redis | 10.96.129.219 / 10.100.119.222 / 10.109.66.124 / 10.108.136.104 / 10.102.119.171 | 80 / 5000 / 80 / 5432 / 6379 |
| jenkins | jenkins | 10.96.84.76 | 80,50000 |
| keycloak | keycloak / keycloak-db | 10.102.197.7 / 10.98.113.113 | 80 / 5432 |
| monitoring | prometheus / alertmanager / ksm / node-exporter / wechat-bridge / grafana / blackbox-exporter | 10.98.134.245 / 10.103.87.112 / 10.107.70.178 / 10.102.182.61 / 10.101.25.208 / 10.106.157.157 / 10.103.101.121 | 9090 / 9093 / 8080 / 9100 / 8080 / 3000 / 9115 |
| sonar | sonarqube / sonar-db | 10.96.49.186 / 10.97.5.233 | 9000 / 5432 |
| artifactory | artifactory-router / artifactory-db | 10.109.31.47 / 10.106.193.165 | 8082 / 5432 |
| podinfo | podinfo / redis | 10.108.211.77 / 10.102.204.126 | 80 / 6379 |
| webapp | backend / frontend | 10.108.143.85 / 10.99.219.124 | 9898,9999 / 80 |

---

## 3. 名称解析：三层，别搞混

| 谁在解析 | 用哪套 | 现状 |
|---|---|---|
| 办公 PC / 浏览器 / curl | Windows `hosts` | 13 条 `192.168.200.210 <name>.corp.local`，**一行一条**（一行塞 13 个会只剩前 9 个生效） |
| 宿主（GitLab、Runner、podman、containerd 宿主侧） | `/etc/hosts` | 同一批域名 → VIP；外加系统 CA 已 `update-ca-trust` |
| Pod 内（Jenkins/Harbor/ArgoCD…） | CoreDNS | `corp.local:53` 权威区，配置在 CM `kube-system/coredns-corp-hosts`，挂在 `/etc/coredns-extra/corp.hosts` |

> Pod 内解析不需要绕公网 DNS，也不依赖宿主 hosts；`getent hosts harbor.corp.local` 在 Jenkins 容器里直接返回 `.210`。

---

## 4. 外部访问链路（浏览器 → 应用）

```
浏览器
  │ 1) DNS: hosts → 192.168.200.210
  ▼
VIP 192.168.200.210:443  (MetalLB L2 宣告, ARP 00:0c:29:33:67:86)
  │ 2) 只有 TCP/UDP 被 kube-proxy DNAT 进 Service；ping 不通是正常现象
  ▼
gateway Pod (ns gateway, 2 副本, externalTrafficPolicy: Local)
  │ 3) nginx.conf：server_name 精确匹配 <host>.corp.local
  │    TLS 用 gateway-tls；后端一律 set $backend <ClusterIP>:<port>（配置里不出现域名）
  ▼
目标 Service ClusterIP ──► 目标 Pod（应用自己按 X-Forwarded-* / 自身 baseURL 生成跳转）
```

要点：

- 网关**不做路径改写、不做 TLS 卸载到后端**（后端仍是明文 http，只信任"来自网关"这件事）。
- 后端的"规范化 URL"（GitLab `external_url`、Keycloak `KC_HOSTNAME`、Harbor `EXT_ENDPOINT`、ArgoCD `url`、Sonar `serverBaseURL`、Jenkins `location.url`）决定它**吐出来的跳转/回调是哪个域名**——这是 `https://*.corp.local` 能统一的关键，改网关配置没用。
- prometheus/alertmanager 走网关 Basic Auth（`monitoring`/`${GATEWAY_BASIC_PASS}`）；Jenkins 页面 403 同理是网关 Basic Auth，不是服务坏了。

---

## 5. 主干 CI 链路（GitLab CI 唯一写 deploy）

```
① 开发 push（https://gitlab.corp.local/root/podinfo，PAT 或账号）
        │  GitLab 触发 pipeline（.gitlab-ci.yml, 4 stage, concurrent=1 的宿主 runner）
        ▼
② GitLab Runner（宿主 systemd，executor=shell，不是 Pod）
        │  克隆 https://gitlab.corp.local/...（靠宿主 /etc/hosts + 内部 CA）
        ▼
③ stage quality  : sonar-scanner（镜像来自 harbor.corp.local/library/sonar-scanner-cli）
        │          扫描 → 等 quality gate（失败即整条流水线终止）
        ▼
④ stage build    : podman build → podman login https://harbor.corp.local
        │          → push harbor.corp.local/apps/podinfo:<40位 sha>
        │          → ci/verify-image.sh 用 **https** 读回 manifest（读不到就拒绝写清单）
        ▼
⑤ stage artifact : 制品（jar/镜像 tar + sha256 + build-info）上传 Artifactory
        │          https://artifactory.corp.local/artifactory/build-artifacts/...
        ▼
⑥ stage manifest : ci/update-manifest.sh 只改 deploy 分支的 newTag
        │          resource_group: deploy-writeback（同一时刻只允许一条流水线写）
        ▼
⑦ deploy 分支新提交
        │  GitLab webhook → ArgoCD，且 ArgoCD 默认每 3 分钟轮询兜底
        ▼
⑧ ArgoCD Application（podinfo / webapp，path=deploy/podinfo|webapp，targetRevision=deploy）
        │  repo-server 拉 https://gitlab.corp.local/root/podinfo.git（deploy 分支）
        │  kustomize 渲染 → apply 到 ns podinfo / webapp
        ▼
⑨ kubelet → containerd 拉镜像（见第 7 节两条路）→ 滚动更新 → HPA 按 metrics-server 调整
```

各 stage 的实际耗时参考：pipeline #32 全绿约 2 分 50 秒（quality 最慢，Sonar 扫描为主）。

**为什么 Jenkins 不在主干**：Jenkins 的 5 个 stage（checkout → build/test → sonar → jib push → artifactory）只产出镜像与制品，不碰 `deploy` 分支；凭据审计结论是"Jenkins 侧没有任何可写 deploy 的凭据"。两条流水线并行存在，但只有 GitLab 那条能推动部署。

### 5.1 Jenkins 独立链路（maven-demo）

```
Jenkins Job (ns jenkins, JCasC 配的 job)
  ├─ 拉代码：http://192.168.200.12/root/demo-maven.git（宿主 IP，直连 GitLab :80）
  ├─ 构建：maven → 单测
  ├─ 扫描：http://192.168.200.12:30091（Sonar NodePort，直连）
  ├─ 推镜像：Jib → https://harbor.corp.local/apps/maven-demo:<ver>
  │         （Jib 走 JVM 信任库 $JAVA_HOME/lib/security/cacerts，里面已灌内部 CA）
  │         （推送后立刻 curl https manifest 读回校验，curl 用系统 CA，所以加了 -k）
  └─ 制品：artifact_sha256 → Artifactory
```

实测 build #8 SUCCESS，日志里 `jib.to.image=harbor.corp.local/apps/maven-demo`，且不再出现 `Attempting again with HTTP`（说明 https 直连成功）。

---

## 6. SSO / OIDC 流量（六系统共用的两条边）

```
浏览器 ──① 点"用 Keycloak 登录"──► 应用(<host>.corp.local)
                                      │ 302 带 redirect_uri=<应用自己的回调>
                                      ▼
                                   Keycloak https://keycloak.corp.local/realms/corp/protocol/openid-connect/auth
                                      │ 用户登录（账号来自 OpenLDAP 联邦，389）
                                      │ 302 回 redirect_uri?code=...
                                      ▼
                                   应用回调端点 ──② 后端直连──► Keycloak /token（拿 id_token）
                                      │                        （Harbor oidc_verify_cert=false、
                                      │                          ArgoCD dex insecureSkipVerify=true、
                                      │                          Jenkins/Sonar 走 JVM cacerts）
                                      ▼
                                   建本地会话（Harbor sid / ArgoCD argocd.token / Jenkins Cookie）
```

| 应用 | client_id | 注册回调（Keycloak） | 应用侧用什么生成回调 |
|---|---|---|---|
| GitLab | `gitlab` | `https://gitlab.corp.local/users/auth/openid_connect/callback` | `external_url` + omniauth `redirect_uri` |
| Jenkins | `jenkins` | `https://jenkins.corp.local/securityRealm/finishLogin` | JCasC `location.url` |
| Harbor | `harbor` | `https://harbor.corp.local/c/oidc/callback` | **`EXT_ENDPOINT`**（唯一由它决定） |
| Sonar | `sonarqube` | `https://sonar.corp.local/oauth2/callback/oidc` | `sonar.core.serverBaseURL` |
| ArgoCD | `argocd-dex`（不是 `argocd`） | `https://argocd.corp.local/api/dex/callback` | `argocd-cm` 的 `url` + dex |
| Artifactory | `artifactory` | `https://artifactory.corp.local/ui/api/v1/oauth2/callback` | JFrog base URL |

> 排障万能第一步：比对"应用实发 `redirect_uri`"与"Keycloak 注册值"，一条 curl 就能看见（见 `docs/03-身份与账号/统一身份SSO-Keycloak.md` §9.5）。

---

## 7. 镜像进出 Harbor 的两条路（最容易踩的坑）

### 7.1 规范路径：域名 + https

```
podman / Jib / GitLab CI ──443──► VIP .210 ──► gateway ──► harbor nginx ──► harbor-core /registry
kubelet/containerd（清单写域名）────► 同上（containerd 用 /etc/containerd/certs.d/harbor.corp.local/hosts.toml 里的内部 CA）
```

认证：`robot$apps+ci-builder`（apps 项目 push/pull）、`robot$library+jenkins-lib-pull`（library 项目 pull）、kubelet 用 imagePullSecret `harbor-regcred`（`podinfo/webapp/jenkins/keycloak/kube-system` 五个命名空间，`dockerconfigjson` 里同时有 `harbor.corp.local` 和旧 IP 两个 key）。

### 7.2 兼容路径：老清单写 `192.168.200.12:30090`

```
containerd 看到镜像名 192.168.200.12:30090/... 
   └─ /etc/containerd/certs.d/192.168.200.12:30090/hosts.toml → server = "https://harbor.corp.local"
      └─ 实际请求 https://harbor.corp.local/v2/...（Host 头也是域名）
         └─ registry 401 的 realm 也随之变成 https://harbor.corp.local/service/token（可正常取 token）
```

**为什么必须留这条路**：`EXT_ENDPOINT` 改成域名后，registry 的 token realm 跟着变 https，而 `.30090` 这个端口是明文 http，所以"按 IP 名直接走 http"必然失败（`http: server gave HTTP response to HTTPS client` / `no basic auth credentials`）。别名让老镜像名自动改道域名，20+ 份静态清单不用动、Pod 重启不会 ImagePullBackOff。

**反过来不要试**：直接把 `EXT_ENDPOINT` 改回 http"保 CI"——Harbor 的 OIDC 回调会一起退回去，登录立刻报 `Invalid parameter: redirect_uri`。

---

## 8. 其他内部流量

| 链路 | 源 → 目的 | 端口/协议 | 说明 |
|---|---|---|---|
| GitLab ↔ PostgreSQL/Redis | 宿主 systemd 组件内部 | 本地 socket / 127.0.0.1 | Omnibus 自带 |
| Harbor ↔ DB/Redis | harbor-core → harbor-database / harbor-redis | 5432 / 6379（ClusterIP） | |
| ArgoCD 组件互联 | argocd-server → repo-server:8081、dex:5556、redis:6379 | ClusterIP | |
| Keycloak ↔ LDAP | keycloak Pod → 宿主 `192.168.200.12:389` | LDAP 明文 | 用户/组联邦，READ_ONLY |
| Keycloak ↔ DB | → keycloak-db:5432 | | |
| metrics-server | kubelet → metrics-server:443 | | HPA 数据源 |
| Prometheus 抓取 | prometheus → localhost:9090、ksm:8080、node-exporter:9100、alertmanager:9093、argocd-metrics:8082、argocd-server-metrics:8083、argocd-notifications:9001 | ClusterIP http | 6/6 up |
| 告警外发 | alertmanager → wechat-bridge:8080 → 企业微信 webhook（**公网，当前仍是占位 URL**） | https 出网 | 真实外发未打通 |
| 镜像转存 | 宿主 podman → `docker.m.daocloud.io`（公网）→ tag → push 域名 | https | quay/k8s.io 在本环境不可达 |

---

## 9. 排障顺序（从外往里，5 步定位到底哪层坏了）

```bash
# 1) 名称解析（客户端）
ping -n 1 harbor.corp.local        # Windows；集群内 getent hosts harbor.corp.local
# 2) TLS/VIP（不关心应用）
curl -k -o /dev/null -w '%{http_code}\n' https://harbor.corp.local/
# 3) 网关转发（看是否 502/504，502=后端不可达，421=Host 不匹配）
kubectl -n gateway logs deploy/gateway --tail=50
# 4) 后端 Service/Pod
kubectl -n harbor get pod,svc
kubectl -n harbor exec deploy/harbor-core -c core -- curl -s localhost:8080/api/v2.0/systeminfo
# 5) 应用自身 baseURL / 回调（SSO 类问题）
curl -s -o /dev/null -D - -k https://harbor.corp.local/c/oidc/login | grep -i location
```

经验值：宿主上 `curl <ClusterIP>` 返回 000 是常态（calico/网络策略），要进 Pod 里测；`kubectl cp` 只认 Pod 名不认 `deploy/xxx`。

---

## 10. 变更影响面提示（改一处会连带哪里）

| 改动 | 连带影响 | 必须同步改 |
|---|---|---|
| 改 Harbor `EXT_ENDPOINT` | registry token realm 跟着变 | containerd `certs.d`（IP 别名 + 域名 CA）、CI `HARBOR_REGISTRY` 与 `verify-image.sh` 的 scheme、Jenkins 共享库/Jib 地址 |
| 改某系统对外域名 | 它的 OIDC 回调变了 | Keycloak 对应 client 的 `redirectUris`（ArgoCD 记得是 `argocd-dex`） |
| 新增系统接 SSO | 要在 Keycloak 建 client | 先 `kcadm get clients -r corp` **全量列一遍**再定 clientId，别按名字猜 |
| 新增域名 | 客户端/集群内解析 | Windows hosts（一行一条）、宿主 `/etc/hosts`、CM `coredns-corp-hosts` 三处 |
| 换 CA / 重签证书 | 所有信任点 | Gateway Secret、宿主 anchors、GitLab trusted-certs、`jenkins-java-cacerts`/`sonar-java-cacerts`、containerd `ca=` 路径、Windows 根存储 |
| 重启节点/Pod | 见第 7 节 | 只要 containerd 的 `certs.d` 在，老 IP 名清单不会断 |

---

## 11. 现场自检一键脚本

| 目的 | 脚本 |
|---|---|
| 抓全量地址/端口/配置事实 | `scripts/gateway/543-flow-inventory.sh` |
| 回调比对（SSO） | `scripts/gateway/510-redirect-debug.sh`、`512-authorize-check.sh`、`527-sso-e2e.sh` |
| 13 域名回归 | `scripts/gateway/539-final-regression.sh` |
| 镜像仓库两条路验证 | `scripts/gateway/513-registry-https-check.sh`、`514-containerd-ca.sh`、`519-containerd-alias.sh` |
| CI 全链路 | `scripts/gateway/523-watch-pipeline32.sh`、`524-post-pipeline-check.sh`、`537-jenkins-build3.sh` |
