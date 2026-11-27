# Harbor + GitLab Runner 自动构建发布链路

> **⚠️ 2026-11-27 起：Harbor 的推/拉地址统一用 `https://harbor.corp.local`**（`EXT_ENDPOINT` 已切成该域名，否则 OIDC 回调对不上、登录报 `redirect_uri`）。本文里的 `192.168.200.12:30090` 属历史记录/直连排障口径；`podman login/push`、`docker pull`、`HARBOR_REGISTRY`、Jib 的 `jib.to.image` 现在都写域名。containerd 侧保留 `192.168.200.12:30090 → https://harbor.corp.local` 别名，老清单不会被拉断。细节见 `docs/03-身份与账号/统一身份SSO-Keycloak.md` §9.5 与 `docs/01-入口与网络/访问层与证书.md` 5.9 第 8 条。

> 目标机：`192.168.200.12`（Rocky Linux 10.2，8 vCPU / 16 GB，根盘 64 GB 已用 45 GB）
> Kubernetes v1.32.13（kubeadm 单节点）+ containerd v2.4.2 + Calico v3.32.3
> 初版：2026-11-25（Harbor + Runner 首次打通）｜**当前形态：2026-11-26（4 stage + GitOps 写 deploy 分支）**

本文前 8 节记录 Harbor / Runner / 清单这套底座怎么搭起来（这部分至今未变），第 4、6、8 节已按**当前 4 stage 流水线**重写。Sonar 与 Artifactory 的细节不在本文，见 `02-流水线与交付/Sonar与Artifactory.md`。

---

## 1. 整体链路（当前）

```
开发者 git push main
      │
      ▼
GitLab (root/podinfo) ──webhook──► GitLab Runner (shell executor, 本机, concurrency=1)
                                        │
       ┌────────────────────────────────┴──────────────────────────────┐
       │ Stage 1 quality-gate   podman run sonar-scanner-cli → Sonar 质量门禁
       │ Stage 2 build-image    podman build -f Dockerfile.ci → push Harbor :<sha> / :latest
       │ Stage 3 artifact-publish  打包 tar.gz + sha256 → Artifactory build-artifacts
       │ Stage 4 update-manifest  sed 改 newTag → commit → push origin deploy
       └────────────────────────────────┬──────────────────────────────┘
                                        ▼
                         GitLab 仓库 deploy 分支（main 只放源码，不再回写）
                                        │
                                        │ ArgoCD 3 分钟轮询 / 硬刷新
                                        ▼
                         ns podinfo（podinfo ×2 + redis）& ns webapp（backend/frontend）
```

| 组件 | 地址 | 凭据 |
|---|---|---|
| Harbor | `https://harbor.corp.local`（直连 `:30090`；`admin` / `${HARBOR_ADMIN_PASS}`，登录走 Keycloak OIDC） | 项目 `apps` 私有；机器人账号 `robot$apps+ci-builder`，secret 在 `/root/harbor-ci-creds.txt` |
| GitLab | http://192.168.200.12（`root` / `${GITLAB_ROOT_PASS}`；PAT `${GITLAB_PAT}`，登录走 Keycloak OIDC） | 应用仓库 `http://192.168.200.12/root/podinfo.git`，项目 id=2，分支 `main` / `deploy` |
| GitLab Runner | `gitlab-runner` systemd，concurrency=1，shell executor | runner id=1，tags `podinfo, shell` |
| SonarQube | http://192.168.200.12:30091（`sonaradmin` / `${SONAR_ADMIN_PASS}`） | 项目 `podinfo`，门禁 `cicd-gate`，CI 令牌走 `SONAR_TOKEN` |
| Artifactory | http://192.168.200.12:30092（UI）／`:30100`（router 备用） | `admin` / `${ARTIFACTORY_ADMIN_PASS}`，仓库 `build-artifacts`（Local/Generic） |
| Keycloak | http://192.168.200.12:30087（`admin` / `${KEYCLOAK_ADMIN_PASS}`，realm `corp`） | 12 用户 4 组，GitLab/Harbor/Jenkins/Sonar/ArgoCD 的统一登录源 |
| ArgoCD | http://192.168.200.12:30080（原生） / `:30082`（中文代理） | `admin` / `${ARGOCD_ADMIN_PASS}`；Application：`podinfo`、`webapp`（均指向 `deploy` 分支） |
| podinfo 应用 | http://192.168.200.12:30095 | 版本 6.17.0（Go） |
| webapp 应用 | http://192.168.200.12:30096 | 前端 → 后端（同一镜像两种角色） |

镜像清单：

| 镜像 | 说明 |
|---|---|
| `192.168.200.12:30090/apps/podinfo:<40位sha>` | CI 构建产物，约 34 MB（alpine 运行时）；流水线只推全 sha，不再推 `latest` |
| `192.168.200.12:30090/apps/redis:7-alpine` | podinfo 缓存依赖，从 daocloud 转存 |
| `192.168.200.12:30090/apps/metrics-server:v0.7.2` | HPA 依赖的指标服务 |
| `192.168.200.12:30090/apps/busybox:v1` | 连通性测试用 |
| `192.168.200.12:30090/library/sonarqube:10.7-community` | Sonar 服务端 |
| `192.168.200.12:30090/library/sonar-scanner-cli:latest` | CI 扫描器（1.01 GB） |
| `192.168.200.12:30090/library/artifactory-oss:7.104.7` | Artifactory 服务端 |

---

## 2. Harbor 部署（K8s + Helm）

无 StorageClass，因此全部使用 **hostPath 静态 PV/PVC**：

| 用途 | hostPath | PV | PVC | 容量 | 属主 |
|---|---|---|---|---|---|
| registry | `/data/harbor/registry` | `harbor-registry-pv` | `harbor-registry-pvc` | 30Gi | 10000:10000 |
| database | `/data/harbor/database` | `harbor-database-pv` | `harbor-database-pvc` | 5Gi | 999:999 |
| jobservice 日志 | `/data/harbor/joblog` | `harbor-joblog-pv` | `harbor-joblog-pvc` | 2Gi | 10000:10000 |
| redis(valkey) | `/data/harbor/valkey` | `harbor-valkey-pv` | `data-harbor-redis-0` | 2Gi | 999:999 |

关键参数（`/root/harbor-values.yaml`）：

```yaml
expose:
  type: nodePort
  tls:
    enabled: false
  nodePort:
    ports:
      http:
        nodePort: 30090
externalURL: http://192.168.200.12:30090
harborAdminPassword: ${HARBOR_ADMIN_PASS}
persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry: { existingClaim: harbor-registry-pvc }
    database: { existingClaim: harbor-database-pvc }
    jobservice: { existingClaim: harbor-joblog-pvc }
trivy: { enabled: false }
notary: { enabled: false }
database: { type: internal }
redis: { type: internal }
```

安装与验证：

```bash
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor -n harbor -f /root/harbor-values.yaml
kubectl -n harbor get pods                      # 7 个 Pod 全 Running
curl -s http://192.168.200.12:30090/api/v2.0/systeminfo | jq .harbor_version
podman login --tls-verify=false -u admin -p '${HARBOR_ADMIN_PASS}' 192.168.200.12:30090
podman push --tls-verify=false 192.168.200.12:30090/apps/busybox:v1
```

> 现状补充：Harbor 已被改为 `auth_mode=oidc_auth`（client `harbor`，groups claim `groups`，auto onboard 开，token 30 min）。`admin` 本地密码仍可用，但网页登录会跳 Keycloak。

### 三个必踩的坑

1. **valkey 的 PVC 名字是固定的**。Harbor 2.15 起内置 KV 从 redis 换成 valkey，StatefulSet 自带 `volumeClaimTemplates`，生成的 PVC 名是 `data-harbor-redis-0`，chart 里的 `existingClaim` 对它无效。必须先手工建同名 PVC 并绑定 PV，Pod 才能调度。
2. **hostPath 属主必须匹配容器 UID**。容器以非 root 运行：database/valkey 是 999，core/registry/jobservice 是 10000。目录归 root 时报 `initdb: could not create directory ... Permission denied`，按 UID 分别 `chown` 即可。
3. **2.15 没有 redis-photon**。早期按旧文档找 `redis-photon` 镜像会以为镜像缺失，实际是 `valkey-photon`。

---

## 3. GitLab Runner

```bash
curl -L -o /usr/local/bin/gitlab-runner \
  https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
chmod +x /usr/local/bin/gitlab-runner
gitlab-runner install --user root --working-directory /root/gitlab-runner
gitlab-runner start
```

注册（**必须用新版 API**，旧接口已废弃）：

```bash
# 1) 先取 runner 认证 token（旧接口 POST /projects/:id/runners 会返回 runner_id is missing）
curl -X POST -H "PRIVATE-TOKEN: $PAT" -H 'Content-Type: application/json' \
  -d '{"runner_type":"project_type","project_id":2,"description":"podinfo-shell-podman","tag_list":"podinfo,shell","run_untagged":false}' \
  http://192.168.200.12/api/v4/user/runners
# 2) 用返回的 glrt- token 注册
gitlab-runner register --non-interactive --url http://192.168.200.12/ \
  --token 'glrt-I_5oiDn2H-...' --executor shell --description podinfo-shell-podman
```

`/etc/gitlab-runner/config.toml` 关键项：`concurrent = 1`、`shell = "bash"`。

---

## 4. CI 流水线（`.gitlab-ci.yml`，当前 4 stage）

| stage | job | 动作 | 实测耗时 |
|---|---|---|---|
| `quality` | `sonar-scan` | `podman run --network host -v $CI_PROJECT_DIR:/usr/src sonar-scanner-cli`，带 `sonar.qualitygate.wait=true`，门禁不过即 fail | 19–35 s |
| `build` | `build-image` | `podman login` → `podman build -f Dockerfile.ci` → push `:<sha>`（全 sha，不推 `latest`）→ `ci/verify-image.sh` 读回校验 | 72 s（无缓存），8 s（层命中） |
| `artifact` | `publish-artifact` | `ci/publish-artifact.sh` 打 `podinfo-<sha>.tar.gz` + 同名 `.sha256`（纯 hash 一行），`curl -T` 上传 Artifactory `build-artifacts/podinfo/<分支>/<sha>/` | 6 s |
| `manifest` | `update-manifest` | `sed` 改 `deploy/podinfo`、`deploy/webapp` 的 `newTag` → commit `[skip ci]` → rebase 后 push **`deploy`** 分支 | 2 s |

项目 CI 变量（`/projects/2/variables`）：`HARBOR_REGISTRY`、`HARBOR_PASS`（masked）、`GIT_PUSH_TOKEN`（masked，值为 PAT）、`SONAR_TOKEN`（masked）、`ARTIFACTORY_USER`、`ARTIFACTORY_PASS`（masked）。

构建用 `Dockerfile.ci`（沿用上游多阶段构建，针对内网加）：

```dockerfile
ENV GOPROXY=https://goproxy.cn,direct
ENV GOSUMDB=off
# 基础镜像来自 docker.m.daocloud.io（内网可达），运行时用 alpine
```

### 流水线五个坑

| 现象 | 原因 | 修法 |
|---|---|---|
| `mapping values are not allowed in this context` | YAML 把命令里的 `commit -m "chore(deploy): x"`、`newTag: ` 当成键值对 | 整行改用 block scalar `>-` 包裹 |
| `invalid username/password` | 用户名 `robot$apps+ci-builder` 里的 `$apps` 被 GitLab 当变量展开 | 脚本里用单引号硬编码用户名，密码仍走变量 |
| `non-fast-forward` 推不上去 | 同一 commit 触发了并行的两条流水线，前者已提交 | push 前 `git fetch` + `git rebase -X theirs FETCH_HEAD` |
| 清单变更又触发新构建 | 没有路径过滤 | 回写提交带 `[skip ci]`；必要时给 build 加 `changes:` 规则 |
| `ci/publish-artifact.sh: No such file or directory` | pipeline 跑在旧 commit（脚本还没进仓库） | 先 push 脚本，再 `POST /projects/2/pipeline?ref=main` 重新触发，不要点 Retry |
| `no properly formatted checksum lines found` | `.sha256` 用 `sha256sum` 默认 `hash  filename` 格式，再 `sha256sum -c` 不认 | `.sha256` 只写 64 位 hash，校验时自行 `echo "$(cat x.sha256)  x.tar.gz" \| sha256sum -c -` 或直接字符串比对 |

---

## 5. 部署清单

### ns podinfo（10 个资源，自写）

| 资源 | 要点 |
|---|---|
| Deployment `podinfo` ×2 | `maxUnavailable: 0` 滚动更新；`readOnlyRootFilesystem`；drop ALL；startup/readiness/liveness 三探针；`runAsUser: 100 / runAsGroup: 101`（镜像 USER 是 `app`，非数字会被 `runAsNonRoot` 拒绝） |
| Deployment `redis` | `--maxmemory 256mb --maxmemory-policy allkeys-lru`，emptyDir 存储 |
| Service `podinfo` | NodePort **30095** |
| ConfigMap `podinfo-config` | `ui_message` / `log_level` / `cache_ttl` |
| HPA | 2→4，CPU 70% |
| PDB | minAvailable 1 |
| NetworkPolicy ×2 | podinfo egress 仅 DNS + redis；redis ingress 仅 podinfo |
| ServiceAccount | — |

两个 Deployment 都必须挂 `imagePullSecrets: harbor-regcred`，否则 Harbor 私有项目拉取报 `no basic auth credentials`。

### ns webapp（11 个资源，来自上游 `deploy/webapp`）

backend + frontend 两个 Deployment、2 个 HPA、2 个 Service（frontend 额外改造成 NodePort 30096）、ServiceAccount/Role/RoleBinding（`reconciler` 与 `webapp`）、Namespace。

用 `deploy/webapp/kustomization.yaml` 做统一覆盖：

```yaml
images:
  - name: ghcr.io/stefanprodan/podinfo
    newName: 192.168.200.12:30090/apps/podinfo
    newTag: <sha>
patches:
  - target: { kind: Deployment, name: backend }   # 加 imagePullSecrets + imagePullPolicy: Always
  - target: { kind: Service, name: frontend }     # type: NodePort / nodePort: 30096
  - target: { kind: HorizontalPodAutoscaler, name: frontend }  # 修正上游错写成 backend 的 scaleTargetRef
```

CI 会同时回写 `deploy/podinfo` 与 `deploy/webapp` 两处 `newTag`（同一次构建发布两套应用）。`deploy/podinfo` 另含 Sonar/Artifactory 之外的基础设施清单：Namespace `demo` 已是空壳（旧的 `demo-app` 与 `:30081` 演示已下线）。

### 基础设施

`manifests/infra/metrics-server.yaml`：v0.7.2，`--cert-dir=/tmp`（默认证书目录无写权限会 panic）、`--secure-port=10250`（与 Service/探针端口一致）、ClusterRole 必须给 `nodes` 的 `get/list/watch`（只给 `nodes/metrics` 会报 `cannot list resource "nodes"`）。

---

## 6. 端到端验证（当前实测）

```
commit dfa6136f → pipeline #27  success
                  ├─ quality   (sonar-scan)        20 s   → QUALITY GATE STATUS: OK
                  ├─ build     (build-image)      8 s    (层缓存命中)
                  ├─ artifact  (publish-artifact) 6 s    → build-artifacts/podinfo/main/dfa6136f/
                  └─ manifest  (update-manifest)  2 s    → deploy = <newTag: dfa6136f...>
ArgoCD 检测到 deploy 分支变更 → 自动同步 → Pod 拉取新镜像（Synced / Healthy）
podinfo /version 返回 commit dfa6136fc7d0c0ff825c33d74aaa38ad818c13d4
制品两端 sha256 一致：d8259f41…4eb024（包内 podinfo / podcli）
```

验证命令：

```bash
# 1) 触发
cd /root/podinfo-src && git commit --allow-empty -m "test: e2e" && git push origin main

# 2) 看流水线
curl -H "PRIVATE-TOKEN: $PAT" "http://192.168.200.12/api/v4/projects/2/pipelines?ref=main&per_page=3" | jq '.[] | {id,status}'

# 3) 看镜像
curl -u admin:${HARBOR_ADMIN_PASS} "http://192.168.200.12:30090/api/v2.0/projects/apps/repositories/podinfo/artifacts?page_size=5" | jq -r '.[] | "\(.tags[0].name) \(.size)"'

# 4) 看质量门禁（用令牌，不要用 admin:admin，那个本地密码已失效）
curl -u "$SONAR_TOKEN:" "http://192.168.200.12:30091/api/qualitygates/project_status?projectKey=podinfo" | jq .projectStatus.status

# 5) 看制品
curl -u admin:${ARTIFACTORY_ADMIN_PASS} "http://192.168.200.12:30092/artifactory/api/storage/build-artifacts/podinfo/main/<sha>" | jq '.children'

# 6) 看部署
kubectl -n podinfo get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
kubectl -n argocd get applications
curl -s http://192.168.200.12:30095/version
curl -s -X POST -d '{"msg":"hi"}' http://192.168.200.12:30096/echo
```

现状：2 个 Application（`podinfo` / `webapp`）全部 `Synced + Healthy`；HPA 读真实 CPU（`podinfo 2%/70%`、`webapp 3%/99%`）；节点内存 12/16 GiB 已用（可用约 2.7 GiB），根盘 72%。

---

## 7. 镜像拉取（containerd 2.x 必做）

containerd 2.4.2 的 CRI 镜像插件是 `io.containerd.cri.v1.images`，旧写法 `[plugins."io.containerd.grpc.v1.cri".registry.mirrors...]` **不生效**：

```toml
[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = '/etc/containerd/certs.d'
```

```toml
# /etc/containerd/certs.d/192.168.200.12:30090/hosts.toml
server = "http://192.168.200.12:30090"
[host."http://192.168.200.12:30090"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
```

改完 `systemctl restart containerd`。不配 `config_path` 的典型报错是 `http: server gave HTTP response to HTTPS client`。

---

## 8. 日常操作（当前）

```bash
# 发版：push main，四个 stage 自动跑完，CI 只写 deploy 分支
git push origin main

# 回滚：在 deploy 分支改回上一个可用 sha（不触发构建，秒级）
git clone http://192.168.200.12/root/podinfo.git && cd podinfo && git checkout deploy
sed -i 's/newTag: .*/newTag: <旧sha>/' deploy/podinfo/kustomization.yaml
git commit -am "revert: podinfo <旧sha>" && git push origin deploy

# 查看流水线日志
curl -H "PRIVATE-TOKEN: $PAT" http://192.168.200.12/api/v4/projects/2/jobs/<job_id>/trace | tail -40

# 手动同步（REST 没有 refresh 端点，用注解）
kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite

# 清理 Harbor 旧 tag（保留最近 5 个）
# Web UI → apps/podinfo → Artifacts → 批量删除
```

发版耗时基线：一次 commit 到新镜像上线约 **2–3 分钟**（扫描 20–35 s + 构建 8–72 s + 制品 6 s + 回写 2 s + ArgoCD 轮询 ≤180 s）。

> 历史对照：初版流水线只有 `build / manifest` 两个 stage，清单写回 `main`，耗时约 2 分钟；pipeline #14 是那一版的验证记录（commit `e654c67`）。
