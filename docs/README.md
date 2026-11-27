# 文档索引（docs/）

本目录按**看问题的角度**分六类，不再平铺 17 个文件。命名规则：`编号-主题` 做目录，文件名用中文、以「是什么」而非「哪个组件」命名；跨文档引用统一用 `docs/分类/文件名.md`。

> 全部内容来自现场实测（`kubectl` / `systemctl` / 各服务 API / 一次真实发版），不是设计稿。凡标注「不要再试」的，是已经踩过并确认做不通的路。

## 30 分钟上手顺序

1. `../README.md`「服务全景」+「凭据总表」—— 先知道有哪些系统、谁能登、口令是什么；
2. `01-入口与网络/CI-CD网络流量.md` —— 一次 push 到上线的 9 步链路，以及四层网络怎么走；
3. `02-流水线与交付/CI-CD流水线.md` —— GitLab CI 四个 stage 每一跳干什么；
4. `04-可观测与告警/可观测性.md` + `告警接入.md` —— 出问题去哪看、告警怎么进群；
5. 其余按需查。

---

## 01-入口与网络（怎么进来、流量怎么走）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [访问层与证书](01-入口与网络/访问层与证书.md) | MetalLB VIP `192.168.200.210` + 内部 CA 通配符证书 + nginx 边缘网关，13 个 `*.corp.local` 域名 | 新机器接不进来、证书报错、要加域名 |
| [CI-CD网络流量](01-入口与网络/CI-CD网络流量.md) | 主干 9 步链路 + Jenkins 独立链路 + 四层流量（名称解析/入口/应用 baseURL/镜像进出）+ 排障五步 | 问"一次提交到底走到哪了""为什么拉不到镜像" |
| [生产架构与改造路线](01-入口与网络/生产架构与改造路线.md) | 现状与生产态的差距、5 条组合原则、P0~P3 改造路线与执行记录 | 要往生产演进、做容量/高可用规划 |

## 02-流水线与交付（代码怎么变成线上 Pod）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [CI-CD流水线](02-流水线与交付/CI-CD流水线.md) | Harbor + GitLab Runner：构建 → 门禁 → 推镜像 → 写 deploy 分支 | 改 `.gitlab-ci.yml`、加新服务流水线 |
| [GitOps与ArgoCD](02-流水线与交付/GitOps与ArgoCD.md) | 清单与源码分家（`main` / `deploy`）、三道门禁、ArgoCD 自动同步与回滚 | 改同步策略、回滚、排查 Synced 不对 |
| [部署与回滚](02-流水线与交付/部署与回滚.md) | 从裸机到 GitLab×ArgoCD 跑通的第一阶段全记录 | 重建环境、补装组件 |
| [Jenkins部署](02-流水线与交付/Jenkins部署.md) | Jenkins 单节点部署、JCasC、PVC、OIDC 安全域 | Jenkins 起不来、改 JCasC |
| [Jenkins流水线](02-流水线与交付/Jenkins流水线.md) | Pipeline + Shared Library（maven-demo，5 stage，只构建不写 deploy） | 改共享库、加 Jenkins 任务 |
| [Sonar与Artifactory](02-流水线与交付/Sonar与Artifactory.md) | 代码扫描门禁与制品归档的部署、CI 接入、凭据口径 | 质量门禁不通过、制品找不到 |
| [镜像与制品拉取](02-流水线与交付/镜像与制品拉取.md) | 镜像从 Harbor 进集群的两条路（域名 https / IP 名 containerd 别名） | 拉私有镜像失败、`no basic auth credentials` |
| [CI凭据治理](02-流水线与交付/CI凭据治理.md) | 方案 A 定义、GitLab 变量 / K8s Secret / Jenkins 凭据全量审计、4 项待收敛、轮换 SOP | 加流水线权限、口令轮换 |

## 03-身份与账号（一套账号登所有系统）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [统一身份SSO-Keycloak](03-身份与账号/统一身份SSO-Keycloak.md) | OpenLDAP → Keycloak（realm `corp`）→ 6 个系统 OIDC 对接，含 `redirect_uri` 与"用户已存在"两类故障的完整修法 | SSO 登录报错、加新系统接 SSO |
| [OpenLDAP目录](03-身份与账号/OpenLDAP目录.md) | `dc=corp,dc=local` 的目录结构、4 个组、overlay 与管理界面 | 改组织架构、查账号归属 |
| [LDAP新增用户手册](03-身份与账号/LDAP新增用户手册.md) | 加一个用户要动的 5 处（LDAP → Keycloak → GitLab → Jenkins 权限 → 业务系统角色） | 新人入职 |

## 04-可观测与告警（出问题怎么发现、通知给谁）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [可观测性](04-可观测与告警/可观测性.md) | Prometheus / ksm / node-exporter / Alertmanager / Grafana（4 张官方看板）/ blackbox，21 个 target | 加抓取目标、看板空、容量告警 |
| [告警接入](04-可观测与告警/告警接入.md) | 18 条规则 5 组、分组与抑制、钉钉加签接入 4 步、实测记录与 errcode 排障 | 加/调规则、告警没进群、要接新通道 |
| [企业微信告警接入教程](04-可观测与告警/企业微信告警接入教程.md) | 复用 `wechat-bridge`：建机器人 → 写 Secret → 重启桥 → 加 Alertmanager 路由 → 端到端验证，附排障与回滚 | 要把 critical 告警接进企业微信群 |

## 05-组件与测试（每个东西是干嘛的、怎么验）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [组件清单](05-组件与测试/组件清单.md) | 七套系统（GitLab / Keycloak / Jenkins / Harbor / SonarQube / Artifactory / ArgoCD）的职责与边界 | 交接、评审、判断"该不该上这套" |
| [验收测试用例](05-组件与测试/验收测试用例.md) | GitLab × ArgoCD 交互测试用例与实测结论 | 回归、验收、演示 |
| [Gerrit实操练习手册](05-组件与测试/Gerrit实操练习手册.md) | `sandbox/lab` 沙箱：登录/SSH key → push 评审 → +2 合入 → 冲突 rebase 全流程，含排障与一键重置 | 想练 Gerrit、评审流程对不齐、冲突不会解 |

## 06-安全与发布（能不能公开、公开前要做什么）

| 文档 | 一句话 | 什么时候看 |
| --- | --- | --- |
| [凭据与泄露审计](06-安全与发布/凭据与泄露审计.md) | 两轮扫描发现的 6 类明文残留与处置、仍然存在的内部信息暴露面、误提交后的清理与轮换优先级 | 上传 GitHub 前、怀疑泄露、轮换口令 |

---

## 维护约定

| 约定 | 说明 |
| --- | --- |
| 新增文档 | 先归到已有 6 类；确实开新类再用 `07-xxx`，不要建"其他/misc" |
| 命名 | 中文、说清"是什么"，不超过 12 个字；不要用版本号或日期做文件名 |
| 引用 | 一律写 `docs/分类/文件名.md`（正斜杠），不要写绝对路径 |
| 改完清单/脚本 | 同步改对应文档的"现状"行，文档里的数字（13 域名 / 21 target / 18 规则）是硬指标，别留旧值 |
| 凭据 | **一律不写明文**：文档写 `${VAR}`、清单写 `${VAR}`（envsubst）、脚本写 `__VAR__`（`python scripts/secrets/render.py` 渲染，Linux 兼容 `render.sh`）；真实值只放根目录 `.env`（不入库），新增变量同步补到 `.env.example` |
| 截图与日志 | 只贴可复现的命令与关键输出，不贴整屏截图 |

> 根目录 `README.md` 是总入口（服务全景、端口、凭据、常用命令）；本文件只负责"文档怎么找"。
---

## 审计记录

| 日期 | 做了什么 | 主要修正 |
| --- | --- | --- |
| 2026-11-27 | 全量事实比对（K8s 对象 / 域名 / 抓取目标 / 规则 / 凭据 / LDAP / 端口 / 容量） | 域名数 12→13、规则 6→18、目标 6→21、`8C/16G→8C/22G`、盘 45G/72%→52G/82%、Pod 46→49；SSO 与访问表的 Harbor 回调/地址改成 https；「external URL 未做」移入已完成；Jenkins 接 Sonar/Artifactory 的「未接」标记已关闭；补监控组件到部署清单；**同时发现 `30-prometheus.yaml` 与线上 CM 不一致（三个 job 被冲掉），已补回清单并恢复 21 target** |

---

## 凭据占位约定

| 载体 | 写法 | 怎么变回真实值 |
| --- | --- | --- |
| 文档（本目录 / 根 README） | `${HARBOR_ADMIN_PASS}` | `set -a; source .env; set +a` 后用 `envsubst` 或直接读环境变量 |
| `manifests/*.yaml` | `${KEYCLOAK_ADMIN_PASS}` 等 | `envsubst < xx.yaml \| kubectl apply -f -`，或 `python scripts/secrets/render.py xx.yaml --out rendered/xx.yaml` |
| `scripts/**/*.sh` | `__KEYCLOAK_ADMIN_PASS__` 等 | `python scripts/secrets/render.py scripts/xx.sh --out rendered/xx.sh`（Windows/Linux 通用）；Linux 也可 `bash scripts/secrets/render.sh` |

新增/改口令的流程：改 `.env` → 改 `.env.example`（同名键）→ 改服务端 Secret → 文档里的变量名不用动（除非新增）。
漏了哪个变量：`python scripts/secrets/render.py --check --quiet` 会逐条报 `[missing]` 并以 3 退出；运行时会留下 `__XXX__` 字样，一眼可见。