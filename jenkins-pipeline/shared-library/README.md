# platform-lib —— 平台流水线共享库

Jenkins 全局共享库（Global Shared Library），把"构建镜像、发制品、跑扫描"这类重复逻辑从
Jenkinsfile 里抽出来，业务仓库只声明阶段顺序与少量参数。

```
vars/                          # 可直接在 Jenkinsfile 里调用的全局步骤
  gitCheckout.groovy           # 统一代码拉取（分支 / 浅克隆 / 凭据）
  sonarScan.groovy             # Sonar 扫描 + 质量门禁判定（不过即 error）
  mavenPackage.groovy          # mvn clean package + 归档 jar + 单测报告
  buildAndPushImage.groovy     # Jib 直接构建并推 Harbor（无 docker daemon）
  publishArtifact.groovy       # jar + sha256 + build-info 推 Artifactory
src/com/corp/platform/
  Defaults.groovy              # 地址/凭据 ID/路径约定（换环境只改这里）
```

## 在 Jenkinsfile 里用

```groovy
@Library('platform-lib') _

pipeline {
    agent any
    stages {
        stage('① 代码拉取') { steps { script { gitCheckout(repo: 'http://192.168.200.12/root/demo-maven.git') } } }
        stage('② Sonar')    { steps { script { sonarScan(appName: 'demo', version: '1.0.1') } } }
        stage('③ 打包')     { steps { script { mavenPackage(appName: 'demo', version: '1.0.1') } } }
        stage('④ 镜像')     { steps { script { buildAndPushImage(appName: 'demo', version: '1.0.1') } } }
        stage('⑤ 制品')     { steps { script { publishArtifact(appName: 'demo', version: '1.0.1', jar: 'target/demo.jar') } } }
    }
}
```

## 约定的凭据 ID（Jenkins 全局凭据）

| ID | 类型 | 用途 |
|---|---|---|
| `gitlab-pat` | UsernamePassword（`root` + PAT） | 拉私有仓库 |
| `harbor-jenkins-ci` | UsernamePassword（`robot$apps+jenkins-ci`） | 推业务镜像 |
| `harbor-lib-pull` | UsernamePassword（`robot$library+jenkins-lib-pull`） | 拉基础镜像 |
| `sonar-token` | String（`squ_...`） | 扫描与门禁查询 |
| `artifactory-admin` | UsernamePassword | 上传制品 |

## 修改生效方式

共享库是"下次构建才生效"：改完 push 到 `main`，下次 pipeline 运行时会重新 clone。
