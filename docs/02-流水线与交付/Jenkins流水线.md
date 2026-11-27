# Jenkins Pipeline + Shared Library 流水线（maven-demo）

> **⚠️ 2026-11-27 起：Harbor 的推/拉地址统一用 `https://harbor.corp.local`**（`EXT_ENDPOINT` 已切成该域名，否则 OIDC 回调对不上、登录报 `redirect_uri`）。本文里的 `192.168.200.12:30090` 属历史记录/直连排障口径；`podman login/push`、`docker pull`、`HARBOR_REGISTRY`、Jib 的 `jib.to.image` 现在都写域名。containerd 侧保留 `192.168.200.12:30090 → https://harbor.corp.local` 别名，老清单不会被拉断。细节见 `docs/03-身份与账号/统一身份SSO-Keycloak.md` §9.5 与 `docs/01-入口与网络/访问层与证书.md` 5.9 第 8 条。

> 实测时间：2026-11-26 02:30（UTC+8）　状态：**已跑通，build #6 SUCCESS，全程 27.4 s**
>
> 本文记录这套流水线「为什么这么做」「怎么从零搭起来」「卡在哪、怎么解的」「怎么验证」。
> 想直接跑：看第 6 节验证清单；想复刻：看第 5 节命令级步骤。

## 1. 一句话结论

`git push` → Jenkins 自动（当前手动触发）执行 5 个 stage：**代码拉取 → Sonar 扫描 + 质量门禁 → Maven 打包 → Jib 构建镜像推 Harbor → jar/sha256/build-info 推 Artifactory**，任一环节失败即中断，不产出半成品。

一次成功构建的实际产出（build #6）：

| 产物 | 位置 | 实测值 |
|---|---|---|
| 运行镜像 | `192.168.200.12:30090/apps/maven-demo:1.0.6` | digest `sha256:7d92b4ff086b…`，124 MB |
| jar | `build-artifacts/maven-demo/main/1.0.6/maven-demo.jar` | 3 575 B，sha256 `997afedd9f9e…5e81` |
| 校验文件 | 同目录 `maven-demo.jar.sha256` | 与 jar 实际 sha256 一致 |
| 构建凭证 | 同目录 `build-info.json` | 含 build 号、commit `e92a727`、镜像地址 |
| 扫描结果 | Sonar 项目 `maven-demo` | 门禁 `cicd-gate` → `OK`（3 条新代码条件全绿） |

集群内拉取验证：用 `imagePullSecret` 起 pod 跑 `java -version`，返回 `openjdk 21.0.13.1 Temurin`，镜像可用。

## 2. 设计取舍：这套环境"逼"出来的三个决定

先讲清楚环境约束，后面所有"奇怪写法"都有原因。

`kubectl -n jenkins get pods` 显示 Jenkins 是一个 **纯 K8s Pod**（`jenkins-9ddcbcc89-t7vsl`），里面有什么：

```
JDK 21 (/opt/java/openjdk, JAVA_HOME 已设，但 java 不在 PATH)
git / curl / unzip / tar        有
mvn / docker / buildah          没有
用户 jenkins uid 1000，home = /var/jenkins_home（10Gi PVC）
```

出口网络：Maven Central 200、docker.io 401（可达）、Harbor 401（可达）、Artifactory 200。

于是定下三条路线：

### 2.1 Maven：shell 直调装在 PVC 上的 tar.gz，不装 maven-plugin

Jenkins 官方 Maven 集成要在"全局工具配置"里挂一个 maven 安装，然后 `tools { maven 'M3' }` 自动下载——这在 K8s Pod 里默认不可用（需要 maven-plugin + 节点上可写的 tools 目录），且插件本身没装。

做法：**把 Maven 解压到 `/var/jenkins_home/tools/apache-maven-3.9.9`（PVC 上，重启不丢）**，在 `Jenkinsfile` 的 `environment` 里把 `MAVEN_HOME/bin` 拼进 `PATH`，共享库统一用绝对路径 `${MAVEN_HOME}/bin/mvn` 调用。好处：不依赖任何插件，`mvn` 行为和在裸机上完全一致。

### 2.2 Sonar：`sonar-maven-plugin` 坐标直调，不装 Sonar 插件 / sonar-scanner

Jenkins 的 SonarQube 插件没装，节点上也没有 sonar-scanner。但 Maven 能直接拉插件：

```
mvn ... org.sonarsource.scanner.maven:sonar-maven-plugin:5.1.0.4751:sonar -Dsonar.token=$SONAR_TOKEN ...
```

质量门禁不能只看 scanner 退出码——**scanner 永远返回 0**，真正拦截在门禁查询。所以 `sonarScan` 扫完主动查一次 `/api/qualitygates/project_status`，`"status":"ERROR"` 才 `error()` 中断。这是这套流水线里唯一"必须自己写判定"的地方。

### 2.3 镜像：Jib，不用 docker build

Pod 里没有 `/var/run/docker.sock`，buildah 在非特权 Pod 里也起不来。**Jib 走 registry API 直接分层上传，天然不需要 daemon**。

- `from` = Harbor `library/eclipse-temurin:21-jre`（宿主机 podman 从 `docker.m.daocloud.io` 拉下再 push 进去的基础镜像）
- `to` = Harbor `apps/maven-demo:<1.0.N>`
- 打完立刻 `curl` 查一次 manifest，`manifest_http=200` 才算推成功（阶段内自带门禁）

## 3. 代码结构：编排在 Jenkinsfile，细节全在共享库

```
jenkins-pipeline/
├── demo-maven/                      ← GitLab: root/demo-maven (id 4)
│   ├── Jenkinsfile                  ← 只有编排 + 传参，无业务细节
│   ├── pom.xml                      ← Java 21 / JUnit5 / surefire 3.2.5 / jib 3.4.4
│   └── src/…/App.java, AppTest.java ← 订单小计/折扣/税 演示类 + 4 个用例
└── shared-library/                  ← GitLab: root/jenkins-shared-library (id 3)
    ├── vars/
    │   ├── gitCheckout.groovy
    │   ├── sonarScan.groovy
    │   ├── mavenPackage.groovy
    │   ├── buildAndPushImage.groovy
    │   └── publishArtifact.groovy
    ├── src/com/corp/platform/Defaults.groovy   ← 地址/凭据 id/路径约定集中处
    └── README.md
```

注册方式（JCasC，`unclassified.globalLibraries`）：

```yaml
unclassified:
  globalLibraries:
    libraries:
      - name: "platform-lib"
        defaultVersion: "main"
        retriever:
          modernSCM:
            scm:
              git:
                remote: "http://192.168.200.12/root/jenkins-shared-library.git"
                credentialsId: "gitlab-pat"
```

`Jenkinsfile` 第一行 `@Library('platform-lib') _` 即生效。**改共享库不需要 reload Jenkins**：Jenkins 下次构建会重新 clone 库（这就是为什么修 bug 只需 push 到库仓库再点构建）。

各 `var` 的职责与关键点：

| var | 作用 | 关键实现 |
|---|---|---|
| `gitCheckout(repo, branch)` | 拉代码、打印短 commit | `checkout` + `git rev-parse --short HEAD` |
| `sonarScan(...)` | 编译到 `compile` + 扫描 + 门禁判定 | 先 `compile`（Java 扫描要 `target/classes`）；门禁用 curl 判定 |
| `mavenPackage(...)` | 打包 + 归档 | `mvn -B -ntp -DskipTests package`，`archiveArtifacts target/*.jar` |
| `buildAndPushImage(...)` | Jib 构建 + 推送 + manifest 校验 | 两个 Harbor robot 分别做 from/to 认证 |
| `publishArtifact(...)` | 上传 jar/sha256/build-info + 回读校验 | `curl -T` 三次上传，再查 `/api/storage/...` 确认 `downloadUri` |

## 4. 五个 stage 详解（附 build #6 实际日志片段）

### ① 代码拉取

```
Obtained Jenkinsfile from git http://192.168.200.12/root/demo-maven.git
+ git rev-parse --short HEAD → e92a727
版本 1.0.6，提交 e92a727
```

版本号规则 `1.0.${BUILD_NUMBER}`，保证 jar 名、镜像 tag、Artifactory 路径三者天然对齐、可追溯。

### ② 静态扫描 Sonar

```
[mvn] compile → BUILD SUCCESS  (02:23:28)
[sonarScan] 查询质量门禁状态（projectKey=maven-demo）
[sonarScan] {"projectStatus":{"status":"OK",...}}
[sonarScan] 质量门禁 OK
```

注意顺序：**先 compile 再 scan**。只编到 `compile` 阶段（不打包、不跑测试），语义仍是"静态扫描"，但满足 Java 分析对字节码的要求。

### ③ Maven 打包

```
[INFO] BUILD SUCCESS  (02:23:33)
Recording fingerprints / Archiving artifacts
[mavenPackage] 打包完成：target/maven-demo.jar (version 1.0.6)
```

`finalName` 固定为 `maven-demo`，后续所有步骤引用 `target/maven-demo.jar`，不随版本号漂移。

### ④ 构建镜像（Jib → Harbor）

```
+ mvn -B -ntp -DskipTests jib:build -Djib.allowInsecureRegistries=true -DsendCredentialsOverHttp=true
  -Djib.from.image=…/library/eclipse-temurin:21-jre  -Djib.from.auth.username=robot$library+jenkins-lib-pull
  -Djib.to.image=…/apps/maven-demo  -Djib.to.tags=1.0.6  -Djib.to.auth.username=robot$apps+jenkins-ci
[INFO] Using credentials from <from><auth> for …/library/eclipse-temurin:21-jre
[INFO] Built and pushed image as …/apps/maven-demo:1.0.6
+ curl … /v2/apps/maven-demo/manifests/1.0.6 → manifest_http=200
[buildAndPushImage] 已推送到 192.168.200.12:30090/apps/maven-demo:1.0.6
```

两个 robot 的原因见 5.3：Harbor 的项目级 robot **不能跨项目授权**，`library`（拉基础镜像）和 `apps`（推业务镜像）必须各一个。

### ⑤ 推送 JFrog

```
+ sha256sum target/maven-demo.jar → 997afedd9f9ec0c6…
+ curl -T … build-artifacts/maven-demo/main/1.0.6/maven-demo.jar
+ curl -T … maven-demo.jar.sha256
+ curl -T … build-info.json
回读 /api/storage/build-artifacts/maven-demo/main/1.0.6/maven-demo.jar → downloadUri 存在
[publishArtifact] http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/1.0.6/
Finished: SUCCESS   (总耗时 27 370 ms)
```

为什么 Artifactory 只放 jar 不放镜像：**Artifactory OSS 没有 Docker registry 能力**（镜像仓那份职责已经在 Harbor），这里承担的是"这次构建交付了什么"的审计凭证——jar 本体、sha256、一条 build-info。两者职责不重叠。

## 5. 从零复刻：命令级步骤

前置：JCasC 已生效（`docs/02-流水线与交付/Jenkins部署.md`），K8s、GitLab、Harbor、Sonar、Artifactory 均在线。

### 5.1 Maven 装进 PVC

```bash
# 在 Jenkins Pod 内（或宿主机上解压后 cp 进 PVC 挂载点）
curl -fsSL https://repo1.maven.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.tar.gz \
  | tar -xz -C /var/jenkins_home/tools/
/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn -v   # Maven 3.9.9 / JDK 21.0.13.1
```

### 5.2 基础镜像进 Harbor `library`

```bash
# 宿主机（有 podman）
podman pull docker.m.daocloud.io/library/eclipse-temurin:21-jre
podman push --creds admin:${HARBOR_ADMIN_PASS} --tls-verify=false \
  docker.io/library/eclipse-temurin:21-jre 192.168.200.12:30090/library/eclipse-temurin:21-jre
```

> 坑：`podman push` **不带 `--creds`** 会报 `unauthorized`（Harbor 已开 OIDC，无匿名 push）。

### 5.3 两个 Harbor robot（项目级，不能跨项目）

```bash
# apps: pull + push
curl -s -u admin:${HARBOR_ADMIN_PASS} -H 'Content-Type: application/json' -X POST \
  http://192.168.200.12:30090/api/v2.0/projects/apps/robots \
  -d '{"name":"jenkins-ci","duration":-1,"level":"project",
      "permissions":[{"kind":"repository","namespace":"maven-demo","access":[{"action":"pull","resource":"repository"},{"action":"push","resource":"repository"}]}]}'

# library: 只 pull
curl -s -u admin:${HARBOR_ADMIN_PASS} -H 'Content-Type: application/json' -X POST \
  http://192.168.200.12:30090/api/v2.0/projects/library/robots \
  -d '{"name":"jenkins-lib-pull","duration":-1,"level":"project",
      "permissions":[{"kind":"repository","namespace":"*","access":[{"action":"pull","resource":"repository"}]}]}'
```

两个硬限制（试过不通，别重试）：

- `duration` 字段**必填**，漏了报 `bad request error duration input: 0`，填 `-1`（长期有效）。
- 项目级 robot **不能授权多个项目**：硬塞 `apps+library` 报 `Project robot account cannot be assigned permissions for multiple projects`。

得到 `robot$apps+jenkins-ci` 与 `robot$library+jenkins-lib-pull` 及其 secret，写入 JCasC 凭据。

### 5.4 五个凭据：JCasC 只写占位，真值在 Secret

**ConfigMap 里不放任何明文口令**。所有敏感值写在 Secret `jenkins-casc-secrets`，以 `envFrom` 注入容器，JCasC 里只留 `${VAR}` 占位：

```yaml
# Deployment 里
envFrom:
  - secretRef:
      name: jenkins-casc-secrets

# JCasC 里
credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword: {id: "gitlab-pat",         password: "${GITLAB_PAT}"}         # GitLab PAT
          - usernamePassword: {id: "harbor-jenkins-ci",   password: "${HARBOR_CI_PASS}"}     # robot$apps+jenkins-ci
          - usernamePassword: {id: "harbor-lib-pull",     password: "${HARBOR_LIB_PASS}"}    # robot$library+jenkins-lib-pull
          - string:           {id: "sonar-token",         secret:   "${SONAR_TOKEN}"}        # squ_…
          - usernamePassword: {id: "artifactory-admin",   password: "${ARTI_PASS}"}          # OSS 只能 admin，见 8
```

创建 Secret（8 个键，含 OIDC client secret 与 breakglass 口令）：

```bash
kubectl -n jenkins create secret generic jenkins-casc-secrets \
  --from-literal=GITLAB_PAT=... --from-literal=HARBOR_CI_PASS=... \
  --from-literal=HARBOR_LIB_PASS=... --from-literal=SONAR_TOKEN=... \
  --from-literal=ARTI_USER=admin --from-literal=ARTI_PASS=... \
  --from-literal=OIDC_CLIENT_SECRET=... --from-literal=BREAKGLASS_PASS=... \
  --dry-run=client -o yaml | kubectl apply -f -
```

实测验证（build #7，Secret 版凭据，SUCCESS 34.7 s）：`${VAR}` 被 JCasC 正常替换，5 个凭据全部可用（checkout/Sonar/Harbor 两个 robot/Artifactory 各走一遍）。

两条注意事项：

- **`credentials:` 必须是 JCasC 的顶层键**，写在 `jenkins:` 之下会让 Jenkins 起不来（见 6.4）。
- **改 Secret 必须 `rollout restart`**：`envFrom` 注入的环境变量不会热更新；`${VAR}` 缺变量时 JCasC 直接启动失败（无默认值），这是有意的"没配好就别起来"。

完整文件：`manifests\jenkins\jenkins-casc-full.yaml`（占位版）、`manifests\jenkins\jenkins-casc-secret.example.yaml`（Secret 模板）。

### 5.5 建 Job

Job 用 REST 建（无 job-dsl 插件），config.xml 是标准 `CpsScmFlowDefinition` + `GitSCM */main` + 脚本路径 `Jenkinsfile`：

```bash
curl -s -u breakglass:${JENKINS_BREAKGLASS_PASS} -b cookie -H "Jenkins-Crumb: $CRUMB" \
  -H 'Content-Type: application/xml' --data-binary @config.xml \
  'http://192.168.200.12:30088/createItem?name=maven-demo-pipeline'
```

现成脚本：`scripts\jenkins\368-create-job.sh`（内含 config.xml 全文）。

## 6. 六次构建的排障记录

这是本轮最值钱的部分——**每次失败都只差一个点，但报错位置都不在根因处**。

| # | 耗时 | 表面报错 | 根因 | 修法 |
|---|---|---|---|---|
| 1 | 6.2 s | `Invalid option type "timestamps"` | 未装 timestamper 插件 | 删掉 `options.timestamps()` |
| 2 | 32.1 s | `Invalid value for 'sonar.java.binaries'` / `No files matching 'target/classes'` | 扫描跑在编译之前，`target/classes` 不存在 | `sonarScan` 改为 `mvn compile sonar:sonar` 一条命令 |
| 3 | 41.6 s | `NoSuchMethodError: No DSL method 'junit'` | 未装 junit 插件 | `mavenPackage` 删掉 `junit testResults:…` |
| 4 | 45.1 s | `Required credentials … not sent because the connection was over HTTP` | Harbor 是 HTTP，Jib 默认拒绝在明文连接上发凭据 | 加 `-DsendCredentialsOverHttp=true` |
| 5 | 25.8 s | 同上（属性写了但没生效） | 属性名写错：**不能带 `jib.` 前缀** | 由 `-Djib.sendCredentialsOverHttp=true` 改为 `-DsendCredentialsOverHttp=true` |
| 6 | 27.4 s | — | — | **SUCCESS** |

三个补充的"不是根因的假象"，排查时别被带偏：

1. **①#1~#3 的 ②③ 阶段看起来全绿**，错误在 `post`/归档段才炸——因为 `junit` 步骤写在 `archiveArtifacts` 之后。
2. **凭据"看起来没加载"**：`/credentials/store/system/domain/_/api/json?tree=credentials%5Bid%2CtypeName%5D` 的方括号**必须 URL 编码**，不编码返回空数组，很容易误判成 JCasC 没生效。
3. **改 JCasC 后热加载不生效**：ConfigMap 非 subPath 挂载有同步延迟。正确姿势是改文件 → `create configmap --dry-run | kubectl apply` → **`kubectl exec` 确认 Pod 内 `/var/jenkins_home/casc/jenkins.yaml` 已是新内容** → `kubectl rollout restart deploy/jenkins`。

### 6.4 唯一一次把 Jenkins 搞挂的操作（务必避开）

把 `credentials:` 缩进到 `jenkins:` 下面：

```
UnknownAttributesException: jenkins: Invalid configuration elements for type class jenkins.model.Jenkins : credentials.
```

Pod 直接 not-ready（JCasC 启动期校验失败）。修法：`credentials:` 提到顶层（`credentials.system.domainCredentials`），或干脆整份重写 `jenkins-casc-full.yaml`（credentials + jenkins + unclassified 三段完整）。

## 7. 验证清单（可直接复制）

```bash
# 1) 构建状态
curl -s -u 'breakglass:${JENKINS_BREAKGLASS_PASS}' \
  'http://192.168.200.12:30088/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result,duration'
# → {"building":false,"result":"SUCCESS","number":6,"duration":27370}

# 2) Harbor 镜像 tag
curl -s -u 'admin:${HARBOR_ADMIN_PASS}' \
  'http://192.168.200.12:30090/api/v2.0/projects/apps/repositories/maven-demo/artifacts?page_size=10'
# → tags: 1.0.6 / latest

# 3) Artifactory 三个文件（OSS 不支持 ?list 列目录，用 HEAD 逐个验）
for f in maven-demo.jar maven-demo.jar.sha256 build-info.json; do
  curl -s -o /dev/null -w "$f -> %{http_code}\n" -I -u 'admin:${ARTIFACTORY_ADMIN_PASS}' \
    "http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/1.0.6/$f"
done
# → 全部 200

# 4) jar 与 sha256 一致（下载回读）
curl -s -u 'admin:${ARTIFACTORY_ADMIN_PASS}' -o j.jar '…/maven-demo.jar'
curl -s -u 'admin:${ARTIFACTORY_ADMIN_PASS}' -o j.sha '…/maven-demo.jar.sha256'
sha256sum j.jar | cut -d' ' -f1; cut -d' ' -f1 j.sha
# → 两行相同：997afedd9f9ec0c60fa69209400981a373ebba19ba3e6412056ea037b84a5e81

# 5) Sonar 门禁
curl -s -u 'sonaradmin:${SONAR_ADMIN_PASS}' \
  'http://192.168.200.12:30091/api/qualitygates/project_status?projectKey=maven-demo'
# → status: OK

# 6) 集群内可拉取（private 项目需 imagePullSecret）
kubectl -n default create secret docker-registry harbor-pull \
  --docker-server=192.168.200.12:30090 \
  --docker-username='robot$apps+jenkins-ci' --docker-password=<robot secret>
# 然后以 imagePullSecrets: harbor-pull 起 pod → java -version 正常
```

一键脚本：`scripts\jenkins\378-verify-e2e.sh`、`379-verify-2.sh`、`382-pull-test.sh`。

## 8. 已知限制（都是"当前环境就是这样"，不是没做完）

| 限制 | 影响 | 是否值得改 |
|---|---|---|
| ~~凭据明文在 ConfigMap~~ | — | **已解决**：值全部搬到 Secret `jenkins-casc-secrets`，JCasC 只留 `${VAR}`，ConfigMap 里已无明文（build #7 验证） |
| Harbor 走 HTTP | 必须开 `sendCredentialsOverHttp`（Jib 会给 WARNING） | 上 TLS（或前置 nginx 自签证书 + `allowInsecureRegistries`） |
| **Artifactory 只能 `admin` 上传** | 权限过宽、审计不清 | **OSS 版无法解决**（证据见下）：`/api/security/users`、`/api/security/permissions` 全部 400 `This REST API is available only in Artifactory Pro`；LDAP 普通账号 `dev01` 实测读 200、写 403。非 admin 用户没有任何可授写权限的机制，只能升级 Pro/Enterprise 或继续用 admin |
| `apps` 私有项目 | 集群部署必须带 `imagePullSecret`（node 侧 `hosts.toml` 无 auth） | 给 namespace 预置 secret，或项目转 public |
| 未装 `timestamper`/`junit`/`ws-cleanup`/`maven-plugin` | 无时间戳、无单测趋势、用 `deleteDir()` 代 `cleanWs()`、Maven 手装 | 装插件后可去掉这些 workaround |
| 止于"推 JFrog" | 未自动部署到集群 | 后续可让 ArgoCD 订阅更新镜像 tag（同 podinfo 的 GitOps 模式） |
| Job 只能手动/API 触发 | `pollSCM` 未配，无 webhook | 需要时加 `triggers { pollSCM('H/5 * * * *') }` 或 GitLab webhook |

## 9. 日常改动姿势（改完怎么才能生效）

| 要改什么 | 改哪里 | 怎么生效 |
|---|---|---|
| 共享库逻辑 | 本地 `jenkins-pipeline\shared-library\vars\*.groovy` → `--put` 到 `/root/jenkins-src/shared-library/vars/` → `git commit && git push origin main` | **下次构建自动重克隆库**，无需 reload |
| 演示工程 / Jenkinsfile | 同上，路径 `/root/jenkins-src/demo-maven/` | 下次构建生效 |
| JCasC（凭据/库注册/OIDC） | 本地 `manifests\jenkins\jenkins-casc-full.yaml` | `create configmap --dry-run \| apply` → 等 ~30 s 确认 Pod 内文件已更新 → `rollout restart` |
| **口令/令牌轮换** | Secret `jenkins-casc-secrets`（模板见 `jenkins-casc-secret.example.yaml`） | 改 Secret 后**必须** `rollout restart`，环境变量才重新注入 |
| Job 配置 | 重新跑 `scripts\jenkins\368-create-job.sh`（覆盖 config.xml） | 立即生效 |

**注意**：JCasC 里 `credentials` 的改动对正在跑的构建不生效，需要重启；共享库改动则完全不需要。

## 10. 相关文件

- `jenkins-pipeline\demo-maven\`：Jenkinsfile、pom.xml、源码、`README.md`
- `jenkins-pipeline\shared-library\`：5 个 var + `Defaults.groovy` + `README.md`（含凭据 ID 表）
- `manifests\jenkins\jenkins-casc-full.yaml`：JCasC（敏感值全为 `${VAR}` 占位）
- `manifests\jenkins\jenkins-casc-secret.example.yaml`：Secret 模板（仓库不放真实口令）
- `manifests\jenkins\10-deployment.yaml`：Deployment（含 `envFrom: secretRef jenkins-casc-secrets`）
- `scripts\jenkins\350~390*.sh`：本轮从探测到验证的脚本（`368-create-job.sh` 可复用建 Job，`378/379/382` 是验证，`385~387` 是 Secret 迁移，`384/388~390` 是 Artifactory 专用账号的失败探测）
- `docs/02-流水线与交付/Jenkins部署.md`：Jenkins 本身的部署、OIDC、权限矩阵
