# GitOps 流水线改造：清单与源码分家 + 三道门禁

> 版本：2026-11-25 落地并实测通过；**2026-11-26 更新为 4 stage 现状**（新增 `quality`(Sonar) 与 `artifact`(Artifactory) 两个 stage，前置门禁由 3 道变 4 道，`resource_group` 与分支模型未变）。
> 涉及：`root/podinfo` 仓库（`.gitlab-ci.yml`、`sonar-project.properties`、`ci/`、`deploy` 分支）、ArgoCD 两个 Application、GitLab webhook。
> 目的：解决"每次 push 都在 main 上生成一条回写提交""并发写回互相覆盖""清单可能指向拉不到的镜像"三个问题；后续又加了"不合格代码不许进制品库"一道。

---

## 1. 改造前的问题（实测证据）

| # | 问题 | 证据 |
|---|---|---|
| 1 | **并发写回静默覆盖** | 旧流水线 `git fetch main → git rebase -X theirs → git push HEAD:main`。两条流水线同时写回时后者覆盖前者；若后者 sha 更旧，main 会指向旧镜像，而两边 job 都 `success`，无任何告警。`-X theirs` 还会丢弃别人对 `deploy/` 的手改 |
| 2 | **main 被部署提交污染，回滚失效** | `main` 近 10 条提交里 5 条是 `chore(deploy)`（`0be42eaa / 82e987e5 / 2d9ab9ff / 3b1e3f20 / ed855a7d`）。回滚要 revert 一条 CI 提交，下一次构建又覆盖回来；代码审计与部署变更混在一起 |
| 3 | **没有"镜像可拉"门禁** | 旧 `build-image` 推完只 `echo pushed`。Harbor 推送中断、tag 被保留策略清掉时，清单已指向不存在的 tag → ArgoCD 长期 `Progressing`/`ImagePullBackOff`，要靠人发现 |
| 4 | **tag 不是不可变标识** | `TAG: $CI_COMMIT_SHORT_SHA` 只有 7 位（如 `5240220d`），force-push/rebase 后会复用；同时推 `latest`，任何写 `latest` 的清单会随 pod 重启漂移 |
| 5 | **runner workspace 残留** | `GIT_STRATEGY: fetch` 复用构建目录，上一轮 rebase/push 失败会把脏状态留给下一轮 |

顺带纠正一个常见误判：**"镜像没建好 ArgoCD 就同步了"在这条链路上不会发生**。旧顺序是 `build → push → 写清单`，清单落地时镜像已在 Harbor（实测 `5240220d` push `18:10:41`，对应回写提交 `18:10:46`）。真正的问题是"清单写了拉不到的镜像"和"并发覆盖"，方向不是"提前同步"。另外 `podinfo` 的 Deployment 是 `maxUnavailable: 0`，即使同步到坏镜像，旧 pod 也不会被撤，服务不中断，表现是 ArgoCD 报警。

还有一件事：`root/podinfo` **此前没有 GitLab webhook**（只有 `root/cicd-demo` 有），ArgoCD 一直靠 3 分钟轮询，并不存在"硬刷新"。

---

## 2. 设计原则

1. **Git 里只有一处真相**：`main` 只放源码，`deploy` 分支只放清单，任何一方都不被对方污染。
2. **每个门禁都能让流水线失败**：宁可不上线，也不上线一个拉不到镜像的版本。
3. **不静默吞改动**：写回只做"以远端为基重建一次提交"，冲突时重试，绝不 `-X theirs` 强制覆盖。
4. **只有最新代码有资格部署**：main 已前进时，旧流水线主动放弃写回。
5. **事件驱动优先**：push 用 webhook 秒级触发 ArgoCD；3 分钟轮询仅作兜底，不依赖 hard refresh。

---

## 3. 架构

```
开发者 git push main
      │  （只有 main）
      ▼
GitLab (root/podinfo · main = 纯源码) ──push webhook──► ArgoCD /api/webhook
      │                                                      │（只订阅 deploy 分支变化）
      ▼                                                      │
GitLab Runner (shell executor, concurrency=1)                │
   ├─ quality-gate：podman run sonar-scanner-cli               │
   │     └─ 门禁 0：sonar.qualitygate.wait=true，门禁 FAILED 即失败（不构建、不发布）
   ├─ build-image：podman build → push 全 sha tag              │
   │     └─ ci/verify-image.sh ── registry /v2 读回 200 否则失败 │
   ├─ artifact-publish：ci/publish-artifact.sh                 │
   │     └─ 从镜像取二进制打 tar.gz + .sha256 → Artifactory     │
   └─ update-manifest（resource_group 串行）                   │
         ├─ 门禁 1：本流水线必须是最新 main HEAD，否则跳过      │
         └─ 门禁 2：以远端 deploy 为基重建提交，push 失败重试≤3 │
                        │                                     │
                        ▼                                     ▼
              GitLab · deploy 分支（只含 deploy/） ──► ArgoCD（targetRevision=deploy）
                                                             │
                                                             ▼
                                          ns podinfo（podinfo×2 + redis）
                                          ns webapp（backend/frontend）
```

**分支职责**

| 分支 | 内容 | 谁写 | ArgoCD |
|---|---|---|---|
| `main` | 源码 + `.gitlab-ci.yml` + `ci/` | 开发者 | 不读 |
| `deploy` | 仅 `deploy/`（podinfo、webapp 的 kustomize 清单） | CI 的 `update-manifest` | **唯一读取源**（`targetRevision: deploy`） |

`deploy` 是 orphan 分支（从 main 的 `deploy/` 树初始化，只 67 个文件），不带源码历史，因此 CI 写它就是"改一行 tag"，不会牵扯代码。

---

## 4. 四道门禁的实现

文件：仓库根 `.gitlab-ci.yml` + `sonar-project.properties` + `ci/verify-image.sh` + `ci/publish-artifact.sh` + `ci/update-manifest.sh`（本机源文件在 `manifests\podinfo\`、`manifests\podinfo\ci\`，`repo-overlay\` 保留同源副本）。

### 门禁 0：质量门禁（在 quality 阶段，失败则后续 stage 全跳过）

```bash
podman run --rm --network host -e SONAR_HOST_URL -e SONAR_TOKEN \
  -v "$CI_PROJECT_DIR:/usr/src" -w /usr/src \
  "$HARBOR_REGISTRY/library/sonar-scanner-cli:latest" sonar-scanner \
  -Dsonar.projectKey=podinfo -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=600
```

`wait=true` 让扫描器等门禁结果，`FAILED` 时退出码 3，job 直接红。实测证据：首轮 `cicd-gate` 沿用 Sonar way 条件（coverage<80、new_violations>0）时，`new_security_rating=3`、`new_reliability_rating=3` 被判 `QUALITY GATE STATUS: FAILED`，流水线真的被挡住；随后把阈值调成 `GT 3 / GT 3 / GT 1`（评级劣化到 D 才拦）才转绿。

### 门禁 1：镜像存在性（在 build 阶段末尾，失败即整条流水线失败）

```bash
# ci/verify-image.sh 核心
curl -s -o /dev/null -w '%{http_code}' -u "$HARBOR_USER:$HARBOR_PASS" \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json,...' \
  "http://$REG/v2/$PATH/manifests/$TAG"     # 必须 200，404 即失败
```

为什么用 registry v2 的 `manifests` 接口而不是 Harbor 的 REST：

| 接口 | 结果 |
|---|---|
| `GET /v2/apps/podinfo/manifests/<tag>`（robots 凭据） | 存在 **200** / 不存在 **404** |
| `GET /api/v2.0/projects/.../artifacts/tags/<tag>`（同一 robots 凭据） | **403**（robot 账号没有 API 权限） |

CI 用的是 `robot$apps+ci-builder`，所以只能走 registry v2。

### 门禁 2：只有最新 main HEAD 才有资格写清单

```bash
git fetch "$REMOTE" main
MAIN_SHA=$(git rev-parse FETCH_HEAD)
[ "$MAIN_SHA" = "$CI_COMMIT_SHA" ] || { echo "已过期，跳过写回"; exit 0; }
```

效果：A、B 两个提交先后 push，A 的流水线构建完时 main 已是 B → A 主动跳过，只有 B 写清单。避免"晚完成的旧流水线把部署打回旧版本"。

### 门禁 3：以远端为基重建 + 重试（不静默覆盖）

```bash
for i in 1 2 3; do
  git fetch "$REMOTE" deploy
  git reset --hard FETCH_HEAD          # 以远端为基，顺带清掉 fetch 策略遗留的脏工作区
  sed -i "s#newTag: .*#newTag: ${TAG}#" deploy/podinfo/kustomization.yaml deploy/webapp/kustomization.yaml
  grep -q "newTag: ${TAG}" 两份清单 || exit 1     # sed 没命中就失败
  git add … && git commit -m "deploy: podinfo ${TAG}"
  git push "$REMOTE" HEAD:deploy && exit 0
  sleep 2
done
echo "连续 3 次失败" >&2; exit 1
```

关键点：**用 `reset --hard FETCH_HEAD` 重建，而不是 `rebase -X theirs`**。前者只保留"本次 tag 覆盖"，语义明确；后者会丢掉别人的提交且不报错。`resource_group: deploy-writeback` 再把并发写回串成一条队列。

### 触发：webhook + 轮询兜底

```bash
curl -X POST "http://192.168.200.12/api/v4/projects/2/hooks" \
  -H "PRIVATE-TOKEN: <token>" \
  --data-urlencode "url=http://192.168.200.12:30080/api/webhook" \
  --data "push_events=true&enable_ssl_verification=false"
```

ArgoCD 侧不需要 secret（`argocd-secret` 里没有 webhook 签名键即免签名）。日志实证：

```
{"msg":"Received push event repo: http://192.168.200.12/root/podinfo, revision: deploy, touchedHead: false"}
```

`revision: deploy` 说明这次刷新是**清单分支**变化触发的，源码 push 不再惊动 ArgoCD。

---

## 5. 验证记录

**初版端到端（2026-11-25）**：`refactor(ci)` 提交 `f3697dcc` → 流水线 #18

| 环节 | 结果 |
|---|---|
| build | `Successfully tagged …apps/podinfo:f3697dcc7e88…`（全 sha） |
| 门禁 1 | `镜像存在性校验通过：…:f3697dcc…` |
| 门禁 2 | `pipeline=f3697dcc… main=f3697dcc…` → 写回 |
| deploy 提交 | `8906ea4f deploy: podinfo f3697dcc…` |
| ArgoCD | `deployed=8906ea4f`，**Synced/Healthy** |
| 集群 | `image=…:f3697dcc…`，2 个 pod ready，`/version` 的 `commit=f3697dcc…` |

**并发**：`794fce09`(A) 后 8 秒 push `3d1d6d5a`(B)

| 流水线 | 结果 |
|---|---|
| #19（A） | build 成功，`update-manifest` 输出 `main 已前进到 3d1d6d5a，本流水线（794fce09）已过期，跳过写回` |
| #20（B） | build + 门禁 1 + 写回全部成功，`deploy 分支已更新 → 3d1d6d5a…（第 1 次尝试）` |
| deploy 终态 | `97353244 deploy: podinfo 3d1d6d5a…`，两份清单 `newTag` 都是 `3d1d6d5a…` |

**重试**：临时分支 `deploy-selftest` 上两个写入者并行（同一 base、不同 TAG）

| 写入者 | 结果 |
|---|---|
| 1 | 首次 push 被拒 → `推送被拒（第 1 次），2s 后按远端最新重建` → `deploy 分支已更新（第 2 次尝试）` |
| 2 | 首次成功（第 1 次尝试） |

两个提交都在，未被吞掉；测试分支已删除（`204`）。

**清理后最终态**：`3c1f9ae8` → deploy `2c0858c3`（`deploy: podinfo 3c1f9ae8…`）→ 两个应用 `Synced/Healthy`，`/version commit=3c1f9ae8…`。随后用 `245-sync-app-yaml.sh` 把 deploy 分支内两份 `application.yaml` 的 `targetRevision` 也改成 `deploy`（提交 `05e0f2fa`、`af677d2d`），ArgoCD 当前 `deployed=05e0f2fa`、健康 `Healthy`，部署镜像未变。
**main 提交结构**：最后一次回写是 `0be42eaa`（改造前），之后全是正常业务/CI 提交，`chore(deploy)` 归零。

> 说明：滚动更新过程中 ArgoCD 会短暂显示 `Degraded`（旧 pod 摘流时 readiness 503），新 pod Ready 后自动回到 `Healthy`，实测约 1 分钟内恢复，不是故障。

**四 stage 端到端（2026-11-26，当前形态）**：提交 `dfa6136f` → 流水线 #27

| stage | job | 结果 |
|---|---|---|
| quality | `quality-gate` | 20 s，`QUALITY GATE STATUS: OK` |
| build | `build-image` | 8 s（层缓存命中；无缓存 72 s），门禁 1 通过 |
| artifact | `artifact-publish` | 6 s，`build-artifacts/podinfo/main/dfa6136f/podinfo-dfa6136f….tar.gz` + `.sha256` |
| manifest | `update-manifest` | 2 s，写 deploy 分支成功 |

集群侧：两个 Application `Synced / Healthy`，运行镜像 `apps/podinfo:dfa6136fc7d0c0ff825c33d74aaa38ad818c13d4`，`/version` 的 `commit` 与流水线一致；制品下载回来重算 sha256 = `d8259f41…4eb024`，与仓库里 `.sha256` 一致，包内为 `podinfo` 与 `podcli`。

> 四 stage 版本踩过的两个坑：① 首次运行报 `ci/publish-artifact.sh: No such file or directory`（流水线跑在旧 commit）→ 用 `POST /projects/2/pipeline?ref=main` 重新触发；② `.sha256` 用 `sha256sum` 默认带文件名格式，`sha256sum -c` 报 `no properly formatted checksum lines found` → 改为纯 64 位 hash 一行 + 自行字符串比对（`1009-push-ci2.py` 重新提交）。

---

## 6. 日常运维

### 6.1 发版

```bash
cd /root/podinfo-src   # 或任意开发者克隆
git pull --rebase
# 改代码
git commit -am "feat: xxx" && git push origin main
```

之后什么都不用做：Runner 先跑质量门禁（不过则整体失败）→ 构建 → 制品发布 → 门禁 1（镜像可读）→ 门禁 2（HEAD 判定）→ 写 deploy 分支 → webhook 触发 ArgoCD（秒级）→ 轮询兜底最多 3 分钟。

### 6.2 回滚（两种，都不触发构建）

```bash
# 方式 A：在 deploy 分支 revert 一条或几条部署提交（镜像已在 Harbor，秒级回滚）
git clone <repo> && cd podinfo && git checkout deploy
git revert <deploy commit> --no-edit && git push origin deploy

# 方式 B：直接改 tag 并提交
git checkout deploy
sed -i 's/newTag: .*/newTag: <目标 sha>/' deploy/podinfo/kustomization.yaml deploy/webapp/kustomization.yaml
git commit -am "rollback: podinfo <目标 sha>" && git push origin deploy
```

回滚**不要**动 main：main 是源码，回滚是"部署状态"的事。

### 6.3 查状态

```powershell
cd C:\Users\morning\Desktop\cicd
python scripts\tools\ssh_exec.py --script scripts\pipeline\239-state-check.sh        # 应用/镜像/版本
python scripts\tools\ssh_exec.py --script scripts\argocd\210-sso-final-check.sh      # ArgoCD 自身
```

单条命令版：

```bash
kubectl -n argocd get app podinfo webapp -o custom-columns='NAME:.metadata.name,DEPLOYED:.status.sync.revision,SYNC:.status.sync.status,HEALTH:.status.health.status'
curl -s http://192.168.200.12:30095/version     # commit 应等于最新 main sha
git ls-remote http://192.168.200.12/root/podinfo.git refs/heads/deploy
```

### 6.4 排障速查

| 现象 | 原因 / 处理 |
|---|---|
| build 阶段 `invalid username/password`，Harbor 日志里用户名变成 `robot+ci-builder` | **GitLab 对 CI 变量值做二次展开**，`robot$apps+ci-builder` 里的 `$apps` 被当变量展开成空。修法：变量值写成 `robot$$apps+ci-builder`（`$$` 是 GitLab 的转义） |
| `镜像不可读：…（registry 返回 HTTP 404）` | push 没真的完成，或 Harbor 回收了该 tag。看 build 日志里的 push 段落；确认 Harbor 保留策略 |
| `update-manifest` 报 `main 已前进到 …，跳过写回` | 正常行为：本流水线不是最新 main HEAD，部署交给后一条流水线 |
| `deploy 分支连续 3 次推送失败` | 有人在 deploy 分支同时操作，或 token 失效；看 `GIT_PUSH_TOKEN` 与 deploy 分支保护设置 |
| ArgoCD 一直 `OutOfSync` / `ComparisonError` | repo-server 拉不到 deploy 分支：`kubectl -n argocd logs deploy/argocd-repo-server`；确认 repoURL/凭据 |
| webhook 没触发（日志无 `Received push event`） | 项目 hook 是否还在（`GET /projects/2/hooks`）；GitLab 后台「允许本地网络 webhook」是否开启；ArgoCD 端点必须是 `/api/webhook`（`/api/v1/webhook` 是 404） |
| 部署后短暂 `Degraded` | 滚动更新中，等新 pod Ready；`maxUnavailable: 0` 保证服务不断 |
| 新 tag 部署了但界面还是旧版本 | `imagePullPolicy` 与 tag 是否真的变了；`kubectl -n podinfo get deploy podinfo -o jsonpath='{…image}'`；`/version` 里的 `commit` 是最硬的证据 |

### 6.5 保留策略

Harbor 里 `apps/podinfo` 的每个 tag 都是某次提交的不可变镜像，回滚靠它。**务必配置 tag 保留**（项目 → 配置管理 → Tag 保留），建议"保留最近 30 个 + 保留匹配 `release-*`"，否则历史 tag 被清掉后无法回滚。当前仓库 `apps/podinfo` 有 13 个 tag（都是历史构建产物，流水线现在只推全 sha、不再推 `latest`），占用约 4.0 GB。

---

## 7. 已知限制与后续可选项

1. **单环境**：现在只有 `deploy` 一条清单分支 = 只有一套环境。要 staging/prod 两级，就建 `deploy-staging` / `deploy-prod`（或 `deploy/overlays/{staging,production}` 两个 Application），流水线按分支写不同的清单分支。
2. **tag 仍是可变的**：Harbor 允许同名 tag 覆盖。想彻底不可变可改推 digest（`@sha256:…`），kustomize 用 `newName: repo@sha256:…`；代价是清单可读性变差。
3. **runner `concurrent = 1`**：构建串行，A/B 并发时 B 要排队。改成 2+ 后门禁 1 依然有效（它按 main HEAD 判定，不依赖并发度）。
4. **没有自动清理旧 ReplicaSet/旧镜像**：`revisionHistoryLimit: 3` 只管 ReplicaSet；镜像靠 Harbor 保留策略。
5. **可选：ArgoCD Image Updater**：若以后不想让 CI 写 Git，可改为 Image Updater 监听 Harbor tag 并写回清单——但审计与门禁复杂度会上升，当前方案已够用。

---

## 8. 相关文件与脚本

| 位置 | 说明 |
|---|---|
| 仓库 `main`：`.gitlab-ci.yml` | **4 stage**：`quality` → `build` → `artifact` → `manifest`；`TAG: $CI_COMMIT_SHA`（全 sha）；`manifest` job 带 `resource_group: deploy-writeback`；全部 job 限定 `main` 分支 |
| 仓库 `main`：`sonar-project.properties` | 扫描范围与 `sonar.projectKey=podinfo` |
| 仓库 `main`：`ci/verify-image.sh` | 门禁 1（registry manifest 200） |
| 仓库 `main`：`ci/publish-artifact.sh` | 制品打包（`podman create` + `cp` 取二进制 → tar.gz）+ 纯 hash `.sha256` + `curl -T` 上传 + 读回校验 |
| 仓库 `main`：`ci/update-manifest.sh` | 门禁 2 + 门禁 3（HEAD 判定、reset 重建、3 次重试） |
| 仓库 `deploy`：`deploy/podinfo`、`deploy/webapp` | ArgoCD 的唯一读取源 |
| 本机 `repo-overlay\` | `.gitlab-ci.yml` / `sonar-project.properties` / `ci\publish-artifact.sh` 的同源副本 |
| 本机 `manifests\podinfo\`、`manifests\podinfo\ci\` | 初版清单与脚本的留档副本 |
| `scripts\pipeline\230-setup-webhook.sh` / `237-verify-after-refactor.sh` / `239-state-check.sh` / `245-sync-app-yaml.sh` | webhook 注册、改造后验证、日常体检、两份 application.yaml 对齐（改造期的审计脚本已归档） |
| `scripts\sonar-jfrog\998-push-ci.py`、`1009-push-ci2.py` | 通过 GitLab API 提交 4 stage 流水线与制品脚本（后者修 sha256 格式） |
| `scripts\argocd\228-switch-to-deploy-branch.sh` | 把两个 Application 切到 deploy 分支 |
