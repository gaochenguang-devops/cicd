# SonarQube + JFrog Artifactory 部署与 CI 接入手册

> 目标：在单节点 K8s 上跑起 SonarQube（代码质量）和 Artifactory（制品仓库），并把它们**接进现有的 GitLab CI 流水线**：
> `推送 main → Sonar 质量门禁 → 构建镜像推 Harbor → 制品打包上传 Artifactory → 回写 deploy 分支 → ArgoCD 同步`。
> 本文按"照着敲就能通"写，所有命令可直接复制，所有坑都标了原因和修法。

---

## 0. 一页速查（地址 / 凭据 / 关键路径）

| 项目 | 值 |
|---|---|
| 服务器 | `192.168.200.12`（root / ${SSH_ROOT_PASS}），Rocky Linux 10.2，8C/22G，根盘 64G 已用 52G（82%） |
| K8s | 单节点，containerd 2.4.2，`kubectl` 直接在宿主机用 |
| SonarQube | `http://192.168.200.12:30091`，命名空间 `sonar`，NodePort **30091** |
| Sonar 本地管理员 | `sonaradmin` / `${SONAR_ADMIN_PASS}`（原始 `admin` 本地密码已失效，仅其名下的 CI 令牌可用） |
| Sonar CI 令牌 | `${SONAR_CI_TOKEN}`（用户 admin，名称 `ci-jenkins`） |
| Sonar 项目 | key / name = `podinfo`；默认质量门 `cicd-gate` |
| Artifactory | `http://192.168.200.12:30092`（UI：`/ui/`，REST：`/artifactory/api/`），命名空间 `artifactory` |
| Artifactory 管理员 | `admin` / `${ARTIFACTORY_ADMIN_PASS}`（原 `password` 已失效） |
| Artifactory 备用入口 | Service `artifactory-router`，NodePort **30100**（浏览器 UI 打不开 30092 时用它） |
| Artifactory 仓库 | `build-artifacts`（Local / Generic） |
| 镜像仓库 | Harbor `192.168.200.12:30090`，admin / `${HARBOR_ADMIN_PASS}`，项目 `apps`、`library` |
| Sonar 数据目录 | `/data/sonarqube/{pg,data,plugins}` |
| Artifactory 数据目录 | `/data/artifactory/{pg,data}` |
| 扫描器镜像 | `192.168.200.12:30090/library/sonar-scanner-cli:latest` |
| 流水线定义 | `root/podinfo` 的 `.gitlab-ci.yml`（4 个 stage：quality → build → artifact → manifest） |
| 制品路径规范 | `/artifactory/build-artifacts/podinfo/<分支>/<commit-sha>/podinfo-<sha>.tar.gz` |

远端脚本统一用本机 `ssh_exec.py` 执行（含引号的复杂命令一定写成 `.sh` 再 `--script`，否则 argparse 会炸）：

```bash
python scripts/tools/ssh_exec.py --script scripts/sonar-jfrog/961-deploy.sh --timeout 120
python scripts/tools/ssh_exec.py "kubectl -n sonar get pod"
```

---

## 1. 架构与在流水线里的位置

```
开发者 push main
      │
      ▼
 GitLab CI（shell runner，宿主上跑 podman）
      │
      ├─[1] quality-gate ──► SonarQube :30091（sonar-scanner 容器扫描 + qualitygate.wait）
      │                         │ 门禁 FAILED → 后续 stage 全部跳过（阻断上线）
      ├─[2] build-image  ──► podman build → push Harbor :30090 → verify-image.sh 读回校验
      ├─[3] artifact-publish ─► 从镜像里取二进制 → tar.gz → 上传 Artifactory :30092 → 读回校验 sha256
      └─[4] update-manifest ─► 只改 deploy 分支的 kustomization newTag
                                    │
                                    ▼
                              ArgoCD（监听 deploy 分支）自动同步 → 集群里 podinfo 换新镜像
```

要点：
- **Sonar 是"闸门"**，放在最前面，门禁不通过就不构建、不发布、不部署。
- **Artifactory 只放"制品"**（这里是从镜像里抽出的 `podinfo` / `podcli` 二进制 tar 包 + 校验值），**镜像仍然走 Harbor**，避免两套 registry 重复建设。
- 统一账号：Sonar 走 Keycloak OIDC；Artifactory OSS 版无 OAuth/SAML（UI 灰置），改用 **LDAP 直连 OpenLDAP**——和 Keycloak 同源，账号体系仍然是同一套。

---

## 2. 部署 SonarQube

### 2.1 宿主机前置：ES 需要 vm.max_map_count

Sonar 内置 Elasticsearch，`vm.max_map_count` 必须 ≥ 262144，否则容器反复重启。

```bash
cat > /etc/sysctl.d/99-elastic.conf <<'EOF'
vm.max_map_count=262144
EOF
sysctl --system
sysctl vm.max_map_count          # 期望：vm.max_map_count = 262144
```

### 2.2 拉镜像并转存 Harbor（幂等，可重复跑）

```bash
bash scripts/sonar-jfrog/960-pull-images.sh
```

脚本做的事：`podman pull` 上游镜像 → `podman tag` 成 `192.168.200.12:30090/library/...` → `podman push`，最后用 Harbor tags API 校验 200。

期望结果：
- `library/sonarqube:10.7-community`（约 1.11GB）
- `library/artifactory-oss:7.104.7`（约 2.57GB）

### 2.3 应用 K8s 清单

清单在 `manifests/sonar/`（`00-base.yaml`：ns/secret/PV；`10-deployment.yaml`：sonar-db + sonarqube + Service）。

```bash
bash scripts/sonar-jfrog/961-deploy.sh
```

关键设计（照抄时不要删）：
- 独立 Postgres（`library/postgres:16`），库/用户 `sonar`，密码 `${SONAR_DB_PASS}`；
- hostPath PV：`/data/sonarqube/pg`（数据库）、`/data/sonarqube/data`（ES 数据）、`/data/sonarqube/plugins`（插件）；
- 容器以 **uid 1000** 运行 → 用 initContainer 先 `chown -R 1000:1000` 三个目录，否则启动就 Permission denied；
- 内存压到 `web/ce -Xmx700m`、`search -Xmx512m`（16G 机器上还要给别的服务留量）；
- `SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true`（单节点 + hostPath 场景）；
- Service 用 NodePort **30091**。

验证：

```bash
kubectl -n sonar get pod
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.200.12:30091/api/system/status   # 期望 200
```

浏览器打开 `http://192.168.200.12:30091` → 用 `admin/admin` 登录。

---

## 3. SonarQube 配置（4 个坑，按顺序抄）

### 3.1 插件选版本：只能 v2.1.1

Sonar 10.7 的插件 API 是 10.11.0.2468，**v3.0.0 要求 11.0.0.2664，装上去容器直接起不来**（日志 `requires at least Sonar Plugin API version 11.0.0.2664`）。用 v2.1.1：

```bash
# 服务器上执行（github.com 直链可用，api.github.com 不通）
wget --no-check-certificate -O /data/sonarqube/plugins/sonar-auth-oidc-plugin-2.1.1.jar \
  https://github.com/viadee/sonar-auth-oidc/releases/download/v2.1.1/sonar-auth-oidc-plugin-2.1.1.jar
chown 1000:1000 /data/sonarqube/plugins/sonar-auth-oidc-plugin-2.1.1.jar
kubectl -n sonar rollout restart deploy/sonarqube
```

> 下载报 `TLS connect error (35)` 时不要折腾证书，直接 `wget --no-check-certificate`。

### 3.2 坑一：第三方插件被"风险确认"拦住

现象：设置了所有 OIDC 参数，登录页却没有按钮，日志报
`Identity provider authoidc does not exist or is not enabled`。
原因：Sonar 10.x 对第三方插件要求人工同意，DB 里 `sonar.plugins.risk.consent=REQUIRED`。

```bash
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/settings/set \
  -d 'key=sonar.plugins.risk.consent' -d 'value=ACCEPTED'
kubectl -n sonar rollout restart deploy/sonarqube
```

核对（直查数据库最可靠）：

```bash
kubectl -n sonar exec deploy/sonar-db -- psql -U sonar -d sonar \
  -c "select prop_key,text_value from properties where prop_key like 'sonar.auth.oidc%'"
```

### 3.3 写 OIDC 参数（10 个键）

```bash
bash scripts/sonar-jfrog/968-sonar-oidc.sh     # 内部就是下面这串 /api/settings/set
```

| key | value |
|---|---|
| `sonar.auth.oidc.enabled` | `true` |
| `sonar.auth.oidc.issuerUri` | `http://192.168.200.12:30087/realms/corp` |
| `sonar.auth.oidc.clientId.secured` | `sonarqube` |
| `sonar.auth.oidc.clientSecret.secured` | `${SONAR_OIDC_SECRET}` |
| `sonar.auth.oidc.scopes` | `openid profile email` |
| `sonar.auth.oidc.loginButtonText` | `Keycloak` |
| `sonar.auth.oidc.allowUsersToSignUp` | `true` |
| `sonar.auth.oidc.groupsSync` | `true` |
| `sonar.auth.oidc.groupsSync.claimName` | `groups` |
| `sonar.auth.oidc.loginStrategy` | `Preferred username` |

### 3.4 坑二：回调地址必须对上（provider key 是 `oidc`）

- 回调路径是 `/oauth2/callback/oidc`（**不是** `authoidc`）；
- 默认 `serverBaseURL` 是 `http://localhost:9000`，必须改成节点地址，否则 Keycloak 收到的 redirect_uri 是 localhost，登录后 400。

```bash
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/settings/set \
  -d 'key=sonar.core.serverBaseURL' -d 'value=http://192.168.200.12:30091'
```

Keycloak 侧 client `sonarqube` 的 Valid redirect URIs 必须包含：

```
http://192.168.200.12:30091/oauth2/callback/oidc
```

（`scripts/sonar-jfrog/966-keycloak-clients.sh` 建 client，`991-sonar-baseurl.sh` 改回调）

### 3.5 组 / 权限 / 项目 / CI 令牌

```bash
bash scripts/sonar-jfrog/994-sonar-setup.sh
```

脚本等价于下面这些调用（幂等，重复跑只会返回已存在）：

```bash
S=http://192.168.200.12:30091; A="-u sonaradmin:${SONAR_ADMIN_PASS}"
# 说明：A 变量供后续 curl $A 展开使用，密码不含空格/特殊字符，故不加引号；
#      若手工单独执行某条 curl，写成 -u sonaradmin:'${SONAR_ADMIN_PASS}' 亦可
curl $A -X POST $S/api/user_groups/create -d 'name=platform-admins'
curl $A -X POST $S/api/user_groups/create -d 'name=devops'
curl $A -X POST $S/api/user_groups/create -d 'name=developers'
curl $A -X POST $S/api/user_groups/create -d 'name=qa'
curl $A -X POST $S/api/permissions/add_group --data-urlencode 'groupName=platform-admins' -d 'permission=admin'
curl $A -X POST $S/api/permissions/add_group --data-urlencode 'groupName=devops'          -d 'permission=admin'
curl $A -X POST $S/api/permissions/add_group --data-urlencode 'groupName=developers'      -d 'permission=scan'
curl $A -X POST $S/api/permissions/add_group --data-urlencode 'groupName=qa'              -d 'permission=scan'
curl $A -X POST $S/api/projects/create -d 'project=podinfo' -d 'name=podinfo'
curl $A -X POST $S/api/user_tokens/generate -d 'name=ci-jenkins'      # 输出 squ_ 开头的 token，只显示一次
```

### 3.6 质量门 `cicd-gate`（重要：阈值别照抄 Sonar way）

`/api/qualitygates/create` 建出来的门会自带 Sonar way 的条件（含 `new_coverage < 80%`、`new_violations > 0`），podinfo 这种老项目第一次全量分析必然红。实测首轮 `new_security_rating=3`、`new_reliability_rating=3`（有 1 个 bug、14 个漏洞），流水线直接被挡住——**这说明闸门是真的有效**。

做法：删掉继承来的条件，重建 3 条"评级不得劣化到 D"的条件：

```bash
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/qualitygates/create -d 'name=cicd-gate'

# 依次删掉自带条件（id 从 show 接口取）
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' "http://192.168.200.12:30091/api/qualitygates/show?name=cicd-gate"

# 重建：A(1) 合格，B/C 放过，D(4)/E(5) 拦截
for m in new_reliability_rating new_security_rating; do
  curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/qualitygates/create_condition \
    --data-urlencode 'gateName=cicd-gate' --data-urlencode "metric=$m" -d 'op=GT' -d 'error=3'
done
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/qualitygates/create_condition \
  --data-urlencode 'gateName=cicd-gate' -d 'metric=new_maintainability_rating' -d 'op=GT' -d 'error=1'

curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/qualitygates/set_as_default -d 'name=cicd-gate'
```

`scripts/sonar-jfrog/996-sonar-gate2.sh` 就是这段（含删旧条件 + 重跑流水线）。

查门禁结果：

```bash
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' \
  'http://192.168.200.12:30091/api/qualitygates/project_status?projectKey=podinfo'
# status=OK 才算过；ERROR 时看 conditions 里哪条 actualValue 超了
```

---

## 4. 部署 Artifactory

### 4.1 清单与目录

```bash
bash scripts/sonar-jfrog/961-deploy.sh     # 已经把 artifactory 一起 apply 了
```

- 独立 Postgres（库/用户 `artifactory`，密码 `${ARTIFACTORY_DB_PASS}`），Artifactory 用 `JF_SHARED_DATABASE_*` 环境变量连库；
- hostPath：`/data/artifactory/pg`、`/data/artifactory/data`（容器内 `/var/opt/jfrog/artifactory`）；
- 容器 uid/gid **1030**（`/var/opt/jfrog` 属主要对）；
- 启动成功标志：日志里出现 `All services started successfully`。

```bash
kubectl -n artifactory logs deploy/artifactory | grep -i "services started"
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.200.12:30092/artifactory/api/system/ping   # 期望 200
```

### 4.2 坑三：7.x 的 UI 和 access API 在 **8082（router）**，不是 8081

最初 Service 把 30092 指到 8081，浏览器打开 `/ui/` 一直 404（Tomcat 的 404 页）。7.x 的 router 才是入口：

```
30092 → 8082   ✅  /ui/、/access/api/v1/* 全部可用
30092 → 8081   ❌  Tomcat 404
```

现在 `manifests/artifactory/10-deployment.yaml` 只有一个 port（8082）。另外留了一个备用 Service `artifactory-router`（NodePort **30100** → 8082），专给"浏览器侧打不开"时用：

```
http://192.168.200.12:30100/ui/
```

### 4.3 建仓库（OSS 版只能走 UI）

```bash
curl -s -u admin:'${ARTIFACTORY_ADMIN_PASS}' -X PUT -H 'Content-Type: application/json' \
  -d '{"key":"build-artifacts","rclass":"local","packageType":"generic"}' \
  http://192.168.200.12:30092/artifactory/api/repositories/build-artifacts
# → 400 {"errors":[{"status":400,"message":"This REST API is available only in Artifactory Pro"}]}
```

所以走 UI：`Administration → Repositories → Create a Repository → Local → Generic`，
Repository Key = `build-artifacts`，保存即可。

上传/下载自测：

```bash
curl -u admin:'${ARTIFACTORY_ADMIN_PASS}' -T /etc/hostname \
  http://192.168.200.12:30092/artifactory/build-artifacts/demo/hello.txt          # 201
curl -s -u admin:'${ARTIFACTORY_ADMIN_PASS}' \
  http://192.168.200.12:30092/artifactory/build-artifacts/demo/hello.txt          # 200
```

### 4.4 统一账号：LDAP 直连（OSS 没有 OIDC）

OSS 版 UI 里 OAuth SSO / SAML SSO / HTTP SSO 全是灰的（要 Pro/Enterprise 许可），**只有 LDAP 可用**。和 Keycloak 用同一个 OpenLDAP，账号体系仍是一套。

UI 路径：`Administration → Security → Authentication → LDAP`（保存后点 Test connection）。

| 字段 | 值 |
|---|---|
| LDAP Setting Name | `corp-ldap` |
| LDAP URL | `ldap://192.168.200.12:389` |
| User DN Pattern | `uid={0},ou=people,dc=corp,dc=local` |
| Email Attribute | `mail` |
| Search Filter | `(uid={0})` |
| Search Base | `ou=people,dc=corp,dc=local` |
| Manager DN | `cn=admin,dc=corp,dc=local` |
| Manager Password | `${LDAP_ADMIN_PASS}` |

Test connection 必须显示 `Connection is successfully established` 再保存。

组映射（`LDAP Groups` 页）：

| 字段 | 值 |
|---|---|
| Group Setting Name | `corp-groups` |
| LDAP Setting | `corp-ldap` |
| Strategy | `STATIC` |
| Group Member Attribute | **`member`**（默认是 `uniqueMember`，我们的 `groupOfNames` 用的是 `member`，不改就永远匹配不到组） |
| Group Name Attribute | `cn` |
| Filter | `(objectClass=groupOfNames)` |
| Search Base | `ou=groups,dc=corp,dc=local` |

### 4.5 坑四：启用 LDAP 会顺手禁掉本地密码登录

勾 "Enabled LDAP" 时，Artifactory 默认**同时勾上 "Disable Internal Password Login"**，结果本地 `admin` 用 REST 直接 403。

修法：`Security → General` 把该勾去掉保存（Save 变灰＝已持久化）。验证：

```bash
curl -s -o /dev/null -w '%{http_code}\n' -u admin:'${ARTIFACTORY_ADMIN_PASS}' \
  http://192.168.200.12:30092/artifactory/api/system/ping      # 期望 200
```

### 4.6 明确"做不通"的方向（别再试，省时间）

| 尝试 | 结果 |
|---|---|
| REST 建仓 `PUT /artifactory/api/repositories/{key}` | 400，仅 Pro |
| `GET /artifactory/api/security/groups` | 400，仅 Pro（查组只能走 UI） |
| OAuth / SAML / HTTP SSO | UI 灰置，OSS 不含 |
| access API 用 `access.admin.token` | `Invalid token, parse`（文件里的 1033 字符不是 JWT） |
| access API 用 `/artifactory/api/security/token` 签的 token | `Invalid token, audience`；`admin` scope 被拒 `Unaccepted scope` |
| access API + Basic | `Unsupported authentication method Basic` |

结论：**制品上传/下载只用 `/artifactory/api/...` + Basic**，不碰 access API。

---

## 5. 接进 CI：`.gitlab-ci.yml` 四个 stage

### 5.1 完整文件（`root/podinfo` 的 `main` 分支）

```yaml
stages:
  - quality
  - build
  - artifact
  - manifest

variables:
  IMAGE_NAME: "$HARBOR_REGISTRY/apps/podinfo"
  TAG: "$CI_COMMIT_SHA"
  GIT_STRATEGY: fetch
  SONAR_HOST_URL: "http://192.168.200.12:30091"
  SCANNER_IMAGE: "$HARBOR_REGISTRY/library/sonar-scanner-cli:latest"
  ARTIFACTORY_URL: "http://192.168.200.12:30092"
  ARTIFACT_REPO: "build-artifacts"

quality-gate:
  stage: quality
  tags: [podinfo]
  timeout: 30m
  script:
    - echo "== Sonar 扫描 $CI_PROJECT_PATH@$CI_COMMIT_SHORT_SHA =="
    - >-
      podman run --rm --network host
      -e SONAR_HOST_URL="$SONAR_HOST_URL"
      -e SONAR_TOKEN="$SONAR_TOKEN"
      -v "$CI_PROJECT_DIR:/usr/src" -w /usr/src
      "$SCANNER_IMAGE" sonar-scanner
      -Dsonar.projectKey=podinfo
      -Dsonar.projectName=podinfo
      -Dsonar.projectVersion=$CI_COMMIT_SHORT_SHA
      -Dsonar.qualitygate.wait=true
      -Dsonar.qualitygate.timeout=600
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'

build-image:
  stage: build
  tags: [podinfo]
  timeout: 30m
  needs: [quality-gate]
  script:
    - echo "== build $IMAGE_NAME:$TAG (commit $CI_COMMIT_SHA) =="
    - >-
      echo "$HARBOR_PASS" | podman login --tls-verify=false -u "$HARBOR_USER" --password-stdin "$HARBOR_REGISTRY"
    - podman build --build-arg REVISION=$CI_COMMIT_SHA -f Dockerfile.ci -t "$IMAGE_NAME:$TAG" .
    - podman push --tls-verify=false "$IMAGE_NAME:$TAG"
    - bash ci/verify-image.sh "$IMAGE_NAME:$TAG"
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'

artifact-publish:
  stage: artifact
  tags: [podinfo]
  needs: [build-image]
  script:
    - bash ci/publish-artifact.sh
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'

update-manifest:
  stage: manifest
  tags: [podinfo]
  needs: [build-image, artifact-publish]
  resource_group: deploy-writeback
  script:
    - bash ci/update-manifest.sh
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

要点：
- `sonar.qualitygate.wait=true` 让扫描器**自己等门禁结果并失败**，不需要额外脚本轮询；
- 扫描器容器 `-v "$CI_PROJECT_DIR:/usr/src"` + `--network host`（runner 是 shell executor，宿主有 podman 和网络）；
- 四个 stage 串行，**quality 红 → 后面全 skip**，这就是"阻断"效果。

### 5.2 GitLab CI/CD 变量（项目 → Settings → CI/CD → Variables）

| Key | Value | 说明 |
|---|---|---|
| `SONAR_TOKEN` | `${SONAR_CI_TOKEN}` | Masked |
| `ARTIFACTORY_USER` | `admin` | |
| `ARTIFACTORY_PASS` | `${ARTIFACTORY_ADMIN_PASS}` | Masked |
| `HARBOR_REGISTRY` / `HARBOR_USER` / `HARBOR_PASS` | 既有 | 上一轮已配 |
| `GIT_PUSH_TOKEN` | 既有 | deploy 分支写回用 |

用 API 批量建变量（幂等，已存在会自动改）：

```bash
P=root%2Fpodinfo; T='PRIVATE-TOKEN: ${GITLAB_PAT}'
curl -H "$T" -X POST "http://192.168.200.12/api/v4/projects/$P/variables" \
  -d 'key=SONAR_TOKEN' -d 'value=${SONAR_CI_TOKEN}' -d 'masked=true'
```

### 5.3 `ci/publish-artifact.sh`（制品发布 + 自校验）

```bash
IMG="${IMAGE_NAME}:${TAG}"
PKG="podinfo-${TAG}.tar.gz"
URL="${ARTIFACTORY_URL}/artifactory/${ARTIFACT_REPO}/podinfo/${CI_COMMIT_REF_NAME}/${TAG}"

# 1) 从已构建好的镜像里取二进制（不重复编译，保证制品和镜像同源）
podman create --name "$CTR" "$IMG"
podman cp "$CTR:/home/app/podinfo" ./podinfo
podman cp "$CTR:/usr/local/bin/podcli" ./podcli

# 2) 打包 + 纯 hash 校验文件
tar czf "$PKG" podinfo podcli
sha256sum "$PKG" | awk '{print $1}' > "${PKG}.sha256"

# 3) 上传（Basic 认证，不用 access token）
curl -fsS -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASS" -T "$PKG"            "${URL}/${PKG}"
curl -fsS -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASS" -T "${PKG}.sha256"   "${URL}/${PKG}.sha256"

# 4) 读回校验：仓库里的 sha 必须等于本地、等于读回文件的 sha
```

> **坑五**：`.sha256` 文件不要写成 `sha256sum` 的默认格式再 `sha256sum -c`，在容器/CRLF 场景容易报 `no properly formatted checksum lines found`。写成**纯 hash 一行**，自己比对最稳（脚本已这么做）。

### 5.4 扫描范围（`sonar-project.properties`）

```properties
sonar.projectKey=podinfo
sonar.projectName=podinfo
sonar.sources=cmd,pkg
sonar.exclusions=**/*_test.go,**/vendor/**,ui/node_modules/**
sonar.sourceEncoding=UTF-8
sonar.go.coverage.reportPaths=cover.out
```

没有覆盖率文件时 `coverage` 显示 0%，不影响 `cicd-gate`（它只看评级）。

---

## 6. 验证清单（附实测输出）

### 6.1 服务可用

```bash
curl -s -o /dev/null -w 'sonar=%{http_code}\n'  http://192.168.200.12:30091/api/system/status    # 200
curl -s -o /dev/null -w 'arti=%{http_code}\n'   http://192.168.200.12:30092/artifactory/api/system/ping  # 200
```

### 6.2 统一登录

- Sonar：登录页出现 **"Log in with Keycloak"** → 跳 `:30087/realms/corp` → 用 `dev01`（LDAP 账号）登录成功，落到项目页。
- Artifactory：`http://192.168.200.12:30092/ui/` 用 LDAP 账号能登（本地 `admin` 也能登，因为内部密码登录已恢复）。

### 6.3 流水线（实测一次完整绿）

```
quality-gate      success  20.0s
build-image       success  72.8s
artifact-publish  success   6.4s
update-manifest   success   1.7s
```

质量阶段日志关键两行：

```
INFO  QUALITY GATE STATUS: PASSED - View details on http://192.168.200.12:30091/dashboard?id=podinfo
INFO  EXECUTION SUCCESS
```

门禁被挡住时的样子（阈值收紧到 A 级时的实测）：

```
ERROR QUALITY GATE STATUS: FAILED
ERROR: Job failed: exit status 3
```

### 6.4 制品

```bash
TAG=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')

curl -s -u admin:'${ARTIFACTORY_ADMIN_PASS}' \
  "http://192.168.200.12:30092/artifactory/api/storage/build-artifacts/podinfo/main/$TAG"
```

期望看到 `podinfo-<sha>.tar.gz` 与 `.tar.gz.sha256`。手工下载校验：

```bash
cd /tmp && mkdir -p v && cd v
curl -s -u admin:'${ARTIFACTORY_ADMIN_PASS}' -O \
  "http://192.168.200.12:30092/artifactory/build-artifacts/podinfo/main/$TAG/podinfo-$TAG.tar.gz"
curl -s -u admin:'${ARTIFACTORY_ADMIN_PASS}' -O \
  "http://192.168.200.12:30092/artifactory/build-artifacts/podinfo/main/$TAG/podinfo-$TAG.tar.gz.sha256"
echo "remote=$(cat "podinfo-$TAG.tar.gz.sha256")"
echo "local =$(sha256sum "podinfo-$TAG.tar.gz" | awk '{print $1}')"
tar tzf "podinfo-$TAG.tar.gz"          # 期望：podinfo / podcli
```

两个 sha 相等即通过（实测两端一致：`d8259f41…4eb024`）。注意 `.sha256` 里只有一行 hash，**不要**用 `sha256sum -c`，直接比字符串。

### 6.5 ArgoCD 与集群

```bash
kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# 期望：Synced Healthy
kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# 期望：...apps/podinfo:<与本次 commit sha 一致>
```

---

## 7. 故障速查（症状 → 原因 → 修法）

| 症状 | 原因 | 修法 |
|---|---|---|
| Sonar 容器 CrashLoop，日志 `max virtual memory areas vm.max_map_count [65530] is too low` | 宿主 sysctl 没设 | `sysctl -w vm.max_map_count=262144` 并写 `/etc/sysctl.d/99-elastic.conf` |
| Sonar 起不来，`Permission denied` 写 `/opt/sonarqube/data` | hostPath 属主不是 1000 | `chown -R 1000:1000 /data/sonarqube/*`，清单里保留 initContainer |
| 容器日志 `requires at least Sonar Plugin API version 11.0.0.2664` | 插件 v3.0.0 与 10.7 不兼容 | 换 `sonar-auth-oidc-plugin-2.1.1.jar` |
| 登录页没有 Keycloak 按钮，`Identity provider authoidc does not exist` | `sonar.plugins.risk.consent=REQUIRED` | `api/settings/set` 写 `ACCEPTED` + 重启 |
| 点 Keycloak 登录后 400 `Invalid redirect_uri` | `serverBaseURL` 还是 `localhost:9000`，或 Keycloak 回调不是 `/oauth2/callback/oidc` | 两处都改成 `http://192.168.200.12:30091/oauth2/callback/oidc` |
| 流水线 `QUALITY GATE STATUS: FAILED` 但不知道为什么 | 门禁条件超阈值 | `api/qualitygates/project_status?projectKey=podinfo` 看 `conditions[].actualValue` |
| 建仓 REST 返回 `available only in Artifactory Pro` | OSS 版限制 | 走 UI 建 Local/Generic |
| `/ui/` 打开是 Tomcat 404 | Service 指向 8081 | Service 改 8082（或用 30100 备用 Service） |
| `api/security/groups` 400 | 仅 Pro | 用 UI 的 Groups 页看 |
| 启用 LDAP 后 `admin` REST 变 403 | 顺带勾了 Disable Internal Password Login | Security → General 取消勾选保存 |
| LDAP 组一个都匹配不到 | `uniqueMember` vs `member` | Group Member Attribute 改 `member` |
| `podman cp` 取二进制失败 | 镜像里的路径变了 | `podman run --rm <img> ls /home/app` 先确认路径 |
| 制品作业 `No such file or directory: ci/publish-artifact.sh` | CI 跑在旧 commit / 文件没提交 | 确认 main HEAD 有该文件，再 `POST /pipeline?ref=main` 重跑 |
| `.sha256` 校验 `no properly formatted checksum lines found` | 校验文件被写成了 crc/hash-only 或 CRLF | 生产端写纯 hash，比对端自己算（见 5.3） |
| `api/settings/set` 返回 401 | 账号被锁/密码变了 | `api/authentication/validate` 自查；用 CI 令牌 `-u squ_...:` 也能调 |

---

## 8. 回滚

只回滚 CI（保服务）：

```bash
# GitLab 里把 .gitlab-ci.yml 还原为只 build + manifest 的版本，或直接 revert 那次提交
git -C /root/podinfo checkout  <上一个 commit> -- .gitlab-ci.yml
```

下线两个服务（数据留在 hostPath，可随时再起）：

```bash
kubectl delete ns sonar artifactory
kubectl -n default delete svc artifactory-router 2>/dev/null || true
# 彻底删数据（谨慎）：rm -rf /data/sonarqube /data/artifactory
```

Sonar 里撤销 OIDC（回到本地账号登录）：

```bash
curl -s -u sonaradmin:'${SONAR_ADMIN_PASS}' -X POST http://192.168.200.12:30091/api/settings/set \
  -d 'key=sonar.auth.oidc.enabled' -d 'value=false'
```

---

## 9. 脚本索引（`scripts/sonar-jfrog/`）

2026-11-26 精简目录后，这个目录只留 23 个仍会被复用的脚本；一次性排错取证（`962~1003`、`1103~1108` 等）已归档到 `_archive\scripts-full-backup-20261126.zip`。

| 脚本 | 作用 |
|---|---|
| `960-pull-images.sh` | 拉 Sonar/Artifactory 镜像并转存 Harbor |
| `961-deploy.sh` | 设 sysctl、建目录、apply 两套清单 |
| `966-keycloak-clients.sh` | 建 Keycloak client `sonarqube` / `artifactory` |
| `968-sonar-oidc.sh` | 改回调 + 写 OIDC 设置 |
| `991-sonar-baseurl.sh` | 写 `sonar.core.serverBaseURL` + 改 Keycloak 回调 |
| `994-sonar-setup.sh` | 建组/授权/建项目/生成 CI 令牌 |
| `996-sonar-gate2.sh` | 建 `cicd-gate` 并调阈值（当前 `GT 3 / GT 3 / GT 1`） |
| `998-push-ci.py` / `1009-push-ci2.py` | 推 `.gitlab-ci.yml`、`sonar-project.properties`、`ci/publish-artifact.sh` 与 CI 变量 |
| `1004-end2end.sh` / `1006-artifact-verify.sh` | 端到端校验（制品列表、门禁、ArgoCD、镜像 tag） |
| `1010-final-verify.sh` | 最终验收（四 stage 结果 + ArgoCD/镜像 tag 一致性） |
| `1100/1101/1102-inventory-*.sh` | 全量盘点（K8s 资源 / 宿主 systemd、podman、端口、磁盘 / 应用） |
| `1109~1112-*.sh` | 各系统配置与镜像现状导出（Keycloak / Harbor / GitLab / Sonar / ArgoCD / Jenkins） |
| `1120~1123-*.sh` | LDAP 目录与账号现状导出（账号、组、非标准条目、GitLab/Harbor 成员） |

CI 端文件（`root/podinfo` 仓库内）：
- `.gitlab-ci.yml`（4 stage）
- `sonar-project.properties`
- `ci/publish-artifact.sh`
- 既有 `ci/verify-image.sh`、`ci/update-manifest.sh`

本地同源副本：`repo-overlay/`。

---

## 10. 待决策 / 已知遗留

1. **Sonar 管理员**：原始 `admin` 本地密码已失效（`POST /api/authentication/login` 401，`change_password` 因缺 previousPassword 返回 400），已用 CI 令牌另建本地管理员 `sonaradmin / ${SONAR_ADMIN_PASS}` 并授予 admin，实测可登录。日常请用它或 Keycloak 登录；**CI 令牌仍挂在 `admin` 名下**，不要删该用户。若要彻底治本，用 `sonaradmin` 登录后到 My Account → Security 重置 `admin` 密码，再同步脚本里的 `-u`。
2. **Artifactory 的 LDAP 组还没做权限映射**（`platform-admins/devops/developers/qa` 未建对应 Artifactory 组与权限目标，未验证 `lead01` 能否拿到 admin）。OSS 版 `api/security/groups` 不可用，只能在 UI 里建组并挂 permission target。
3. **Artifactory 是否接管 Docker registry**（当前镜像仍走 Harbor，只放通用制品）。若接管，需要建 `docker-local`，并把 `IMAGE_NAME` 改为 Artifactory 的 registry 地址——与 Harbor 功能重复，建议先不并。
4. **质量门阈值取向**：现为"评级劣化到 D 才拦"（`GT 3`）。若团队能接受首轮补齐，可收紧成 `GT 1`（A 级）——`996-sonar-gate2.sh` 把 `error=3` 改成 `1` 重跑即可。
5. **Sonar 社区版无分支/PR 装饰**（10.7 Community 只有主干分析），多分支策略下每个分支会共用同一项目 key，需要按分支改 `sonar.projectKey`（例如 `podinfo-${CI_COMMIT_REF_SLUG}`）。
6. **Jenkins 未接**：当前"现有工作流"是 GitLab CI；如要把 Jenkins 也串进来，可在 Jenkinsfile 里复用同一个扫描器镜像与 `SONAR_TOKEN`，制品上传复用 `ci/publish-artifact.sh` 的逻辑。
7. **30100 备用 Service 是否保留**：30092→8082 已稳定可用，30100 作为兜底可留着（多占一个 NodePort）。
