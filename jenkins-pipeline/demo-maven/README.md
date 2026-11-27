# demo-maven —— 平台标准流水线的演示工程（可选）

一个极小的 Java 21 / Maven 工程，用于验证 `platform-lib` 共享库的 5 段流水线：
代码拉取 → Sonar 静态扫描 → Maven 打包 → Jib 构建镜像（推 Harbor）→ 制品发布（推 JFrog）。

## 本地跑

```bash
mvn -B clean package          # 编译 + 单测，产出 target/maven-demo.jar
mvn -B jib:build              # 需要 Harbor 凭据，见 README
```

## Jenkins 上跑

Job 名 `maven-demo-pipeline`，SCM 指向本仓库，脚本路径 `Jenkinsfile`。
版本号自动取 `1.0.<BUILD_NUMBER>`，镜像 tag 与制品路径都跟它走，便于回滚对齐。

产物：
- 镜像 `192.168.200.12:30090/apps/maven-demo:1.0.<N>`
- 制品 `http://192.168.200.12:30092/artifactory/build-artifacts/maven-demo/main/1.0.<N>/`
