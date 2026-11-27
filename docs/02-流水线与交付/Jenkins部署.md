# Jenkins 部署说明（192.168.200.12）

> 2026-11-25 部署；**2026-11-26 认证已改为 Keycloak OIDC**。单节点 K8s 内以 Deployment + hostPath PVC 运行，数据落宿主机 `/data/jenkins`，登录走 Keycloak（client `jenkins`，scopes 含 `groups`），权限仍用全局矩阵。
>
> 现状要点：① 认证 = `oicSecurityRealm`（OIDC），不再是 LDAP 直连；② `globalMatrix: Overall/Administer:platform-admins`（组名来自 OIDC 的 `groups` claim）；③ `numExecutors=2`；④ **Jenkins 目前不参与主流水线**——不跑 Sonar 扫描、不传 Artifactory 制品，主链路是 GitLab CI。第 7 节"LDAP 抓包"段落为历史排障记录，留作理解 JCasC 登录机制的参考。

## 1. 访问信息

| 项 | 值 |
|---|---|
| 地址 | **http://192.168.200.12:30088** |
| Agent 端口（TCP） | `192.168.200.12:30089` → 容器 50000 |
| 版本 | Jenkins **2.580.3**（镜像 `jenkins/jenkins:lts-jdk21`，JDK 21） |
| 镜像地址 | `192.168.200.12:30090/library/jenkins:lts-jdk21`（Harbor `library` 项目，public） |
| 数据目录 | 宿主机 `/data/jenkins`（PV `jenkins-home`，10Gi，hostPath，reclaimPolicy=Retain） |
| 命名空间 | `jenkins` |
| 管理员 | Keycloak/LDAP 组 `platform-admins` 成员（如 `lead01`） |
| 普通用户 | `devops` / `developers` 组成员：只读 + 可触发构建 |
| 账号密码 | LDAP 初始密码 `${LDAP_USER_INIT_PASS}`（与 GitLab/Harbor/Sonar 一致，密码校验在 OpenLDAP） |

**登录方式：点「使用 Keycloak 登录」**（`http://192.168.200.12:30087/realms/corp/...` 回调）。本地 admin 与 `initialAdminPassword` 均未使用——`oicSecurityRealm` 生效后本地账号不能登录。

## 2. 架构

```
浏览器 ──► NodePort 30088 ──► Service jenkins ──► Pod (jenkins ns)
                                                   ├── 容器 jenkins
                                                   │    ├── /var/jenkins_home ← PVC ← hostPath /data/jenkins
                                                   │    └── /var/jenkins_home/casc/jenkins.yaml ← ConfigMap jenkins-casc
                                                   └── initContainer install-plugins（jenkins-plugin-cli 装插件）

认证：Jenkins oicSecurityRealm ──OIDC──► Keycloak realm corp ──federation──► OpenLDAP
授权：GlobalMatrixAuthorizationStrategy（platform-admins=管理员；devops/developers=可构建）
```

为什么这样选：

- **跑在 K8s** 而不是再起一个 podman 容器：和现有 ArgoCD/Harbor 同一套调度与端口管理，`kubectl` 就能看状态。
- **hostPath + Retain**：单节点没有 StorageClass，`jenkins_home` 用宿主机目录最直观；Pod 重建/升级不会丢数据。
- **CASC（Configuration as Code）**：OIDC 与权限全部写在 `jenkins.yaml`（ConfigMap `jenkins-casc`），进 Git 可审计，改配置不用点 UI。
- **插件由 initContainer 预装**：镜像首启时不必联网装插件，Pod 起来即可用。

## 3. 清单

本机 `manifests\jenkins\`：

| 文件 | 内容 |
|---|---|
| `00-base.yaml` | Namespace、PV/PVC、ConfigMap（`jenkins.yaml`：`oicSecurityRealm` + globalMatrix + 系统消息 + URL） |
| `10-deployment.yaml` | Deployment（Recreate 策略 + initContainer 装插件 + 探针 + 资源限制）、NodePort Service |

关键参数：

- `strategy: Recreate`：PVC 是 RWO 宿主机目录，不能两份 Jenkins 同时写。
- `runAsUser/fsGroup: 1000`，宿主机目录需 `chown 1000:1000`。
- 插件清单：`configuration-as-code oic-auth git workflow-aggregator credentials-binding matrix-auth kubernetes`（连带依赖共 70 个）。
- 资源：requests 250m/512Mi，limits 2C/2Gi；`JAVA_OPTS=-Xmx1024m`；`numExecutors=2`。
- 探针：startup/readiness 都打 `/login`，避开匿名 403 的 `/`。

## 4. 部署步骤（可重放）

```powershell
cd C:\Users\morning\Desktop\cicd
python scripts\tools\ssh_exec.py --script scripts\sonar-jfrog\1101-inventory-host.sh   # 现状盘点（端口/资源/镜像源）
python scripts\tools\ssh_exec.py --script scripts\jenkins\304-pull-image.sh      # 官方镜像转存 Harbor
python scripts\tools\ssh_exec.py --put "manifests\jenkins\00-base.yaml=>/root/jenkins-manifests/00-base.yaml"
python scripts\tools\ssh_exec.py --put "manifests\jenkins\10-deployment.yaml=>/root/jenkins-manifests/10-deployment.yaml"
python scripts\tools\ssh_exec.py --script scripts\jenkins\307-deploy.sh
python scripts\tools\ssh_exec.py --script scripts\jenkins\322-verify-perms.sh
```

手动等价命令：

```bash
mkdir -p /data/jenkins && chown -R 1000:1000 /data/jenkins
kubectl create ns jenkins
kubectl -n podinfo get secret harbor-regcred -o yaml | sed 's/namespace: podinfo/namespace: jenkins/' | kubectl -n jenkins apply -f -
kubectl apply -f /root/jenkins-manifests/00-base.yaml
kubectl apply -f /root/jenkins-manifests/10-deployment.yaml
```

> OIDC 改了 JCasC 之后不再需要 `jenkins-ldap` secret（旧 secret 若还在可删）。改 ConfigMap 后必须 `rollout restart` 或 `POST /configuration-as-code/reload`。

## 5. 权限矩阵（实测）

| 身份 | 结果 |
|---|---|
| 匿名 | `/` 403，`/login` 200 |
| `dev01`（developers） | 登录成功，authorities 含 `ROLE_DEVELOPERS` / groups；`/manage/` 403、`/script` 403 |
| `ops01`（devops） | 登录成功，authorities 含 `ROLE_DEVOPS` / groups；`/manage/` 403 |
| `lead01`（platform-admins） | 登录成功，`/manage/` 200、`/script` 200（管理员） |

对应 `jenkins.yaml`：

```yaml
securityRealm:
  oicSecurityRealm:
    clientId: jenkins
    clientSecret: ${JENKINS_OIDC_SECRET}
    tokenServerUrl: http://192.168.200.12:30087/realms/corp/protocol/openid-connect/token
    authorizationServerUrl: http://192.168.200.12:30087/realms/corp/protocol/openid-connect/auth
    userInfoServerUrl: http://192.168.200.12:30087/realms/corp/protocol/openid-connect/userinfo
    scopes: "openid profile email groups"
    userNameField: preferred_username
    fullNameFieldName: name
    groupsFieldName: groups
    disableSslVerification: true
authorizationStrategy:
  globalMatrix:
    permissions:
      - "Overall/Administer:platform-admins"
      - "Overall/Read:authenticated"
      - "Item/Read:authenticated"
      - "Item/Build:devops"
      - "Item/Build:developers"
      - "View/Read:authenticated"
```

`groups` 必须由 Keycloak client 的 group membership mapper 输出，否则矩阵里只认 `authenticated`。

## 6. 日常运维

**看状态**

```bash
kubectl -n jenkins get pod,svc,pvc
kubectl -n jenkins logs deploy/jenkins --tail=50
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.200.12:30088/login
```

**改配置（OIDC client、权限、系统消息）**

1. 改本机 `manifests\jenkins\00-base.yaml` 里的 `jenkins.yaml`（同时也改 K8s ConfigMap `jenkins-casc`）；
2. `--put` 到 `/root/jenkins-manifests/` 并 `kubectl apply`；
3. 等 30~60 秒让 ConfigMap 挂载同步，用管理员会话触发 `POST /configuration-as-code/reload`（脚本 `316-set-matrix.sh` 有完整带 Crumb 的写法）；
4. 若只是重启即生效，也可 `kubectl -n jenkins rollout restart deploy/jenkins`。

> 改 OIDC 前先在 Keycloak 侧确认 client `jenkins` 的 redirect URI 是 `http://192.168.200.12:30088/securityRealm/finishLogin`，secret 与 ConfigMap 里一致，否则重启后直接锁在门外。

**装插件**

改 `10-deployment.yaml` 里 initContainer 的 `--plugins` 列表（空格分隔），`kubectl apply` 后 rollout restart；插件已落 `/data/jenkins/plugins`，重启不会重装。

**备份**

```bash
tar czf /root/jenkins-home-$(date +%F).tar.gz -C /data jenkins --exclude=jenkins/war --exclude=jenkins/workspace
```

`/data/jenkins` 里 `jobs/`、`users/`、`credentials.xml`、`plugins/` 是核心；`war/` 是每次启动解包可丢。

**升级**

`podman pull docker.io/jenkins/jenkins:lts-jdk21` → tag/push 到 Harbor → `kubectl -n jenkins set image deploy/jenkins jenkins=<新tag>`（initContainer 的镜像也同步改）。升级前先备份。

## 7. 踩过的坑（都别再试）

1. **镜像名不是 `library/jenkins`**：Docker Hub 上 Jenkins 官方镜像是 `jenkins/jenkins`，`library/jenkins` 报 `manifest unknown`；DaoCloud 镜像站还把 jenkins 列入"不在白名单"。最终直接从 `docker.io/jenkins/jenkins:lts-jdk21` 拉取（走 podman 配置的 mirror 失败后自动回退官方源）成功。
2. **JCasC 全局授权符号是 `globalMatrix`**：写 `authorizationStrategy: matrix` 会抛 `UnknownAttributesException: No AuthorizationStrategy implementation found for matrix`，而且是在 boot 阶段 → CrashLoopBackOff。矩阵插件的 CASC 配置器类只有 `GlobalMatrixAuthorizationStrategyConfigurator` / `ProjectMatrixAuthorizationStrategyConfigurator`。
3. **登录调试必须带 `Jenkins-Crumb`**（LDAP 时代记录，OIDC 下同样适用）：Jenkins 2.580 的登录表单含隐藏 crumb。直接用 `j_username/j_password` POST 会 302 到 `/loginError`，且不会发起任何认证请求。正确姿势：先 GET `/login` 拿 crumb（`name="Jenkins-Crumb" ... value="..."`），再带 `Jenkins-Crumb` 提交。切到 OIDC 后 `j_username` 表单已不存在，脚本化验证请走 `curl -c jar -L 'http://192.168.200.12:30088/securityRealm/commenceLogin?from=%2F'` 跟着 302 到 Keycloak，或直接用 REST API + API Token。
4. **同一 cookie 会话不能换用户登录**：同一 JSESSIONID 先登 dev01 再登 lead01 会被判失败；每个用户用独立 cookie jar。
5. **hostPath 权限**：容器以 uid 1000 运行，宿主机 `/data/jenkins` 必须 `chown 1000:1000`，否则 `Permission denied (13)`。
6. **引导顺序**：首次启动若 JCasC 直接写 `globalMatrix` 也可（已验证重启后正常）；当时为了排错先用 `loggedInUsersCanDoAnything` 起服务，再用 reload 切到 globalMatrix。保留这个套路可作为"配置写坏后的救急"：临时把 ConfigMap 里的授权策略换成 `loggedInUsersCanDoAnything`，重启即恢复登录，改好再 reload。

## 8. 与 Sonar / Artifactory 接线（未做，方案如下）

Jenkins 现在是独立可用的，但没有接进质量与制品链路。要接的话按下面三步：

```groovy
// 1) 质量门禁：在构建前插一个 stage
stage('Sonar') {
  steps {
    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
      sh '''podman run --rm --network host -e SONAR_HOST_URL=http://192.168.200.12:30091 \
        -e SONAR_TOKEN=$SONAR_TOKEN -v "$WORKSPACE:/usr/src" -w /usr/src \
        192.168.200.12:30090/library/sonar-scanner-cli:latest sonar-scanner \
        -Dsonar.projectKey=<项目key> -Dsonar.qualitygate.wait=true'''
    }
  }
}
```

```groovy
// 2) 制品上传：Jenkins 自带 Artifactory 插件（需装 artifactory 插件）或直接 curl
sh '''curl -u "$ARTI_USER:$ARTI_PASS" -T dist/app.tar.gz \
  "http://192.168.200.12:30092/artifactory/build-artifacts/<项目>/jenkins/${BUILD_NUMBER}/app.tar.gz"'''
```

3. 凭据统一放 Jenkins Credentials（`sonar-token`、`arti-user`、`arti-pass`），不要写进 Jenkinsfile；仓库侧建议用 GitLab Project Access Token（只读该仓库）而不是 root PAT。

其余可选：

- **K8s 动态 agent**：已装 `kubernetes` 插件，配 cloud 后可用 `podTemplate` 跑构建，避免污染 master（当前 master 有 2 个 executor）。
- **和现有流水线的关系**：GitLab CI 已覆盖 podinfo 的"扫描→构建→制品→部署"，Jenkins 更适合"需要人工审批/长流程/多仓库编排"的任务，两者并存不必互相替代。
- **HA/多副本**：当前 `replicas: 1` + Recreate，是单点；要做高可用需换 NFS/CephFS 共享存储并拆 controller/agent，单节点环境下不划算。

## 9. 相关脚本

见 `scripts\README.md` 的 `jenkins\` 小节（301~323）：探测、拉镜像、部署、登录/权限验证、以及排障用的抓包与 JCasC 错误解析脚本，全部可重放。
