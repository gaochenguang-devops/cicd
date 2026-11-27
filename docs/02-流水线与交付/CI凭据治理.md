# CI 收敛（方案 A）与凭据治理

> **⚠️ 2026-11-27 起：Harbor 的推/拉地址统一用 `https://harbor.corp.local`**（`EXT_ENDPOINT` 已切成该域名，否则 OIDC 回调对不上、登录报 `redirect_uri`）。本文里的 `192.168.200.12:30090` 属历史记录/直连排障口径；`podman login/push`、`docker pull`、`HARBOR_REGISTRY`、Jib 的 `jib.to.image` 现在都写域名。containerd 侧保留 `192.168.200.12:30090 → https://harbor.corp.local` 别名，老清单不会被拉断。细节见 `docs/03-身份与账号/统一身份SSO-Keycloak.md` §9.5 与 `docs/01-入口与网络/访问层与证书.md` 5.9 第 8 条。

> 落地日期：2026-11-27　　状态：**方案 A 已确立并落地标注；凭据已完成全量审计，发现 4 项待收敛**
> 一句话：**只有一条链路能写 `deploy` 分支（GitLab CI），Jenkins 只做独立任务；两套凭据各自单一来源，谁都不多拿一把钥匙。**

---

## 1. 方案 A 是什么（和方案 B 的差别）

| | 方案 A（**采用**） | 方案 B（放弃） |
| --- | --- | --- |
| 发布写回 | 只有 GitLab CI 的 `update-manifest` 阶段写 `deploy` 分支 | 两条链路都能写，靠 `resource_group` 互斥 |
| Jenkins 定位 | 独立任务：构建 / 门禁 / 制品推送，**只读仓库** | 第二套完整发布链路 |
| 凭据归属 | K8s Secret（Jenkins 侧）+ GitLab CI Variables（GitLab 侧），各自只读自己需要的 | 两边各一套、且有重叠 |
| 审计断点 | 1 个（`deploy` 分支的提交只能来自 GitLab CI） | 2 个，出问题要两边比对 |
| 代价 | Jenkins 不能再"顺手"改清单 | 无 |

**为什么不用方案 B：** 两个写入口 = 两套并发控制 = 两边门禁口径必须永远同步。`resource_group` 只是"防撞车"，不是"防越权"；一旦 Jenkins 里的凭据被误用，`deploy` 分支上会出现无法归因的提交。

---

## 2. 两条链路现状（实测口径）

### 2.1 GitLab CI（主链路，唯一写 `deploy`）

| 阶段 | 动作 | 关键约束 |
| --- | --- | --- |
| `quality-gate` | Sonar 扫描 + `sonar.qualitygate.wait=true` | 门禁 `cicd-gate` 不过则整条失败 |
| `build-image` | podman build + push 到 `apps` 项目 | 宿主 shell executor，`concurrency=1`，tag `podinfo` |
| `artifact-publish` | jar + sha256 + build-info 推 Artifactory `build-artifacts` | Generic Local 仓 |
| `update-manifest` | 改 `deploy` 分支镜像 tag 并 push | `resource_group: deploy-writeback` |

### 2.2 Jenkins（独立任务，**不写 `deploy`**）

`maven-demo-pipeline`，5 个 stage：拉代码 → Sonar + 门禁 → Maven 打包 → Jib 推 Harbor → jar/sha256/build-info 推 Artifactory。最近一次 `build #7 SUCCESS 34.7s`。

已在任务描述里写死定位（实测写入成功）：

> 独立任务（方案A）：仅做 构建/质量门禁/制品推送，只读仓库、不写 deploy 分支，不参与发布写回。发布写回唯一归口 GitLab CI 的 update-manifest 阶段。

```bash
# 复现这条标注（crumb + cookie 两步不能省）
CRUMB=$(curl -s -c /tmp/ck.txt -u 'breakglass:${JENKINS_BREAKGLASS_PASS}' \
  http://192.168.200.12:30088/crumbIssuer/api/json | python3 -c 'import json,sys;print(json.load(sys.stdin)["crumb"])')
curl -u 'breakglass:${JENKINS_BREAKGLASS_PASS}' -b /tmp/ck.txt -H "Jenkins-Crumb: $CRUMB" \
  --data-urlencode "description=独立任务（方案A）…" \
  http://192.168.200.12:30088/job/maven-demo-pipeline/submitDescription
```

> 注意：直接 POST 不带 crumb 会 403；`submitDescription` 是 Jenkins 里改任务描述的正式端点，不要用改 `config.xml` 的方式（会顺带覆盖其它配置）。

---

## 3. 凭据全量审计（2026-11-27 实跑结果）

### 3.1 GitLab 侧（项目级 CI 变量）

| 变量 | masked | protected | 用途 | 判定 |
| --- | --- | --- | --- | --- |
| `HARBOR_USER` | false | false | robot 用户名（非机密） | 正常 |
| `HARBOR_PASS` | **true** | false | robot 口令 | ⚠ 建议 `protected` |
| `HARBOR_REGISTRY` | false | false | 仓库地址 | 正常 |
| `GIT_PUSH_TOKEN` | **true** | false | **写 `deploy` 分支** | ⚠ **必须** `protected` |
| `SONAR_TOKEN` | **true** | false | 门禁查询 + 扫描 | ⚠ 建议 `protected` |
| `ARTIFACTORY_USER` | false | false | 制品上传账号 | 正常 |
| `ARTIFACTORY_PASS` | **true** | false | 制品上传口令 | ⚠ 建议 `protected` |

- `root/cicd-demo`（1）、`root/demo-maven`（4）**无变量**（干净）。
- 实例级 / 群组级变量：`[]`（无全局越权变量，这是好事，保持）。

### 3.2 Jenkins 侧（K8s Secret `jenkins-casc-secrets`，8 键）

| 键 | 用途 | 判定 |
| --- | --- | --- |
| `GITLAB_PAT` | 拉私有仓库 | ⚠ 若是全权限 PAT，应换**项目级 Deploy Token（只读）** |
| `HARBOR_CI_PASS` | 推 `apps` 项目 | 正常（robot `robot$apps+jenkins-ci`） |
| `HARBOR_LIB_PASS` | 拉 `library` 基础镜像 | ⚠ **冗余**：`library` 是 public，匿名即可拉 |
| `SONAR_TOKEN` | 扫描 + 门禁 | 正常 |
| `ARTI_USER` / `ARTI_PASS` | 制品上传 | ⚠ OSS 硬限制：只能用 admin（已实测非 admin 写 403） |
| `OIDC_CLIENT_SECRET` | Jenkins 登录 | ⚠ 与构建凭据**混放**在同一 Secret |
| `BREAKGLASS_PASS` | 应急登录 | ⚠ 同上，应急口令不该和 CI 凭据同库 |

### 3.3 Jenkins 内部凭据（5 个 id，供 Pipeline 引用）

| id | 说明 | 判定 |
| --- | --- | --- |
| `gitlab-pat` | 拉私有仓库 | 见上，建议换 Deploy Token |
| `harbor-jenkins-ci` | `apps` 推送 | 正常 |
| `harbor-lib-pull` | `library` 拉取 | ⚠ 冗余，可删（public 项目匿名可拉） |
| `sonar-token` | 扫描 | 正常 |
| `artifactory-admin` | 上传 | OSS 限制所致，**接受现状** |

**结论：没有发现 Jenkins 持有"能写 `deploy` 分支"的凭据** —— 方案 A 的"单一写入口"在凭据层面成立。

---

## 4. 待收敛项（按风险排序，含具体动作）

### 4.1 【高】`GIT_PUSH_TOKEN` 应设 `protected`

- 现状：`masked=true`、`protected=false` —— 意味着**任何分支的流水线都能拿到这个写 `deploy` 的令牌**（包括 MR 分支、临时分支）。
- 动作：GitLab → Settings → CI/CD → Variables → 勾选 Protected（先确认 `deploy` 是 protected branch，否则 `update-manifest` 会拿不到变量而失败）。
- 验证：在非保护分支跑一次流水线，`update-manifest` 应因缺变量而跳过/失败；在主分支跑，应正常写回。

```bash
# 先确认 deploy 是否受保护
curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  'http://192.168.200.12/api/v4/projects/2/protected_branches' | python3 -m json.tool | head -20
```

### 4.2 【高】Jenkins 的 `GITLAB_PAT` 换项目级 Deploy Token

- 现状：一个 PAT 被用来 clone `root/demo-maven`，权限范围通常大于"只读一个仓库"。
- 动作：GitLab 项目 4 → Settings → Repository → Deploy tokens：`read_repository` → 生成 → 写入 Secret 的 `GITLAB_PAT`（或改名为 `GITLAB_DEPLOY_TOKEN`）→ JCasC 里凭据 id `gitlab-pat` 的值同步 → 重启 Jenkins。

### 4.3 【中】删掉 Jenkins 的 `harbor-lib-pull`

- 依据：`library` 项目 `public=true`，节点与 Pod 匿名可拉（已实测）。
- 动作：先确认 Job 的 Jib 配置里没有显式引用 `harbor-lib-pull`，然后删凭据 + 删 Secret 键 `HARBOR_LIB_PASS`。
- 收益：少一个长期口令，少一个轮换对象。

### 4.4 【中】Secret 拆分：CI 凭据 ≠ 登录凭据

现在 `jenkins-casc-secrets` 里同时装着 `OIDC_CLIENT_SECRET` / `BREAKGLASS_PASS`（**人的登录凭据**）和 `HARBOR_CI_PASS` / `SONAR_TOKEN` / `ARTI_PASS`（**机器凭据**）。一旦为了轮换 CI 令牌而改这个 Secret，会连带重启 Jenkins 的登录配置。

建议拆成两个：

| Secret | 内容 | 谁用 |
| --- | --- | --- |
| `jenkins-auth-secrets` | `OIDC_CLIENT_SECRET`、`BREAKGLASS_PASS` | JCasC 安全域 |
| `jenkins-ci-secrets` | `GITLAB_PAT`、`HARBOR_CI_PASS`、`SONAR_TOKEN`、`ARTI_USER`、`ARTI_PASS` | Pipeline |

Deployment 用两个 `envFrom`，JCasC 模板里 `${OIDC_CLIENT_SECRET}` 等占位照旧可用（变量仍在进程环境里）。

> 注意（已踩过）：`kubectl set env --from=secret/...` 会展开成一个个 `secretKeyRef`，`envFrom` 为空；改 Secret 后必须 `rollout restart` 才生效，且 `envFrom` 变更本身会触发滚动。

### 4.5 【低】GitLab 非机密变量保持 `masked=false`

`HARBOR_USER`、`HARBOR_REGISTRY`、`ARTIFACTORY_USER` 不勾 masked 是对的：masked 只对"需要隐藏的值"有意义，滥用会让日志里出现 `[MASKED]` 而看不出实际仓库地址。

---

## 5. 凭据矩阵（收敛后的目标态）

| 能力 | GitLab CI | Jenkins | 说明 |
| --- | --- | --- | --- |
| 读源码 | `GIT_PUSH_TOKEN`（同时具备写 deploy） | Deploy Token（只读一个项目） | Jenkins 不需要写 |
| 推镜像 `apps` | `HARBOR_USER`/`HARBOR_PASS`（robot `gitlab-ci`） | `harbor-jenkins-ci`（robot `jenkins-ci`） | **两个 robot，互不共用**（当前共用需确认，见 6.1） |
| 拉 `library` | 匿名 | 匿名 | 不需要凭据 |
| Sonar 扫描 | `SONAR_TOKEN` | `SONAR_TOKEN` | 同一 CI 令牌可接受（只读门禁 + 提交扫描） |
| 推制品 | `ARTIFACTORY_USER`/`ARTIFACTORY_PASS` | `ARTI_USER`/`ARTI_PASS`（admin） | OSS 限制，接受 |
| 写 `deploy` | ✅ 唯一 | ❌ | 方案 A 的核心约束 |

> 矩阵是给人看的"问责表"：任何新增能力先问一句——**这一列是不是本来就不该有？**

### 5.1 待确认的一个隐患

GitLab CI 的 `HARBOR_USER` 与 Jenkins 的 `harbor-jenkins-ci` 是否指向**同一个 robot**？如果两边共用 `robot$apps+jenkins-ci`，那么"吊销 Jenkins 凭据"会同时打断主链路。核对方式：

```bash
curl -s -u admin:${HARBOR_ADMIN_PASS} 'http://192.168.200.12:30090/api/v2.0/robots' | \
python3 -c 'import json,sys;[print(r["name"], r.get("level"), r.get("permissions")) for r in json.load(sys.stdin)]'
```

期望态：`robot$apps+gitlab-ci`（主链路）与 `robot$apps+jenkins-ci`（Jenkins）两个独立账号。若不是，按 5.2 建号后改变量。

```bash
# 建独立 robot（duration=-1 必须显式带上，否则 400）
curl -s -u admin:${HARBOR_ADMIN_PASS} -X POST \
  'http://192.168.200.12:30090/api/v2.0/robots' -H 'Content-Type: application/json' -d '{
    "name":"gitlab-ci","duration":-1,"level":"project",
    "permissions":[{"kind":"project","namespace":"apps","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]}]}'
```

---

## 6. 轮换 SOP（任一凭据泄露时照做）

1. **定位影响面**：查第 5 节矩阵 → 该凭据被哪条链路用 → 会不会打断发布；
2. **先建新、再换用、后吊销**：Harbor 建新 robot → 改变量/Secret → 跑一次流水线验证 → 删除旧 robot；
3. **改 GitLab 变量**：API `PUT /projects/:id/variables/:key`（或 UI），改完触发一次流水线；
4. **改 K8s Secret**：`kubectl -n jenkins create secret generic … --dry-run=client -o yaml | kubectl apply -f -` → `rollout restart deploy/jenkins` → 查 `build #N`；
5. **留痕**：在 `docs/02-流水线与交付/CI凭据治理.md` 第 7 节记录"谁、何时、换了什么、验证结果"。

---

## 7. 轮换与变更记录

| 日期 | 对象 | 动作 | 验证 |
| --- | --- | --- | --- |
| 2026-11-27 | Jenkins Job 描述 | 写入"独立任务（方案A）"标注 | `submitDescription` 302 → 描述已更新 |
| 2026-11-27 | 凭据全量审计 | GitLab 7 变量 / K8s Secret 8 键 / Jenkins 5 id 全量对照 | 无 Jenkins→`deploy` 写凭据 |
| （待办） | `GIT_PUSH_TOKEN` | 勾 Protected | 非保护分支拿不到变量 |
| （待办） | `gitlab-pat` | 换项目级 Deploy Token | Jenkins 构建仍 SUCCESS |
| （待办） | `harbor-lib-pull` | 删除 | 构建仍 SUCCESS |
| （待办） | `jenkins-casc-secrets` | 拆成 auth / ci 两个 | Jenkins 启动 + 构建均正常 |

---

## 8. 验收清单

- [x] Jenkins 任务描述明确"独立任务、不写 deploy"
- [x] Jenkins 凭据清单核对：无写 `deploy` 的令牌
- [x] GitLab 无实例级/群组级变量
- [x] `cicd-demo`、`demo-maven` 项目无冗余变量
- [ ] `GIT_PUSH_TOKEN` 改 Protected
- [ ] `gitlab-pat` 换 Deploy Token
- [ ] 删除 `harbor-lib-pull` / `HARBOR_LIB_PASS`
- [ ] Secret 拆分（auth / ci）
- [ ] 确认 GitLab 与 Jenkins 用的是两个独立 Harbor robot

> 前 4 项是"审计结论"，后 5 项是"待执行动作"。没做完之前，方案 A 的结构成立，但"最小权限"只做到一半。

---

## 9. 与其它文档的关系

- 主链路细节：`docs/02-流水线与交付/CI-CD流水线.md`、`docs/02-流水线与交付/GitOps与ArgoCD.md`
- Jenkins 侧：`docs/02-流水线与交付/Jenkins流水线.md`
- 制品拉取：`docs/02-流水线与交付/镜像与制品拉取.md`
- 为什么要收敛：`docs/01-入口与网络/生产架构与改造路线.md` P3 / P1-4
- 脚本：`scripts/ci/600-audit-credentials.sh`（审计）、`scripts/ci/601-Jenkins-scope.sh`（打标注 + 凭据核对）
