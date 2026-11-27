#!/usr/bin/env groovy
/**
 * sonarScan —— 静态扫描 + 质量门禁判定（门禁不过直接失败）
 *
 * 用法：
 *   sonarScan(appName: 'maven-demo', version: '1.0.42', branch: 'main')
 *
 * 说明：
 *   - 用 maven 的 sonar 插件跑扫描，不需要在节点上额外装 sonar-scanner（Jenkins 是纯 K8s Pod，没装 docker）
 *   - 扫描完主动查 /api/qualitygates/project_status，而不是只看 scanner 退出码：
 *     scanner 永远返回 0，真正拦截发生在门禁查询这一步
 */
def call(Map cfg) {
    if (!cfg.appName) {
        error('[sonarScan] 缺少必填参数 appName')
    }

    String host = cfg.sonarHost ?: 'http://192.168.200.12:30091'
    String key = cfg.projectKey ?: cfg.appName
    String mvnc = cfg.mvn ?: '/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn'

    withCredentials([string(credentialsId: cfg.sonarCredId ?: 'sonar-token', variable: 'SONAR_TOKEN')]) {
        sh """
            # Java 扫描需要字节码（target/classes），所以先 compile 再 scan；
            # 只编到 compile 阶段，不跑单测、不打包，语义仍是"静态扫描"
            ${mvnc} -B -ntp -DskipTests compile \
              org.sonarsource.scanner.maven:sonar-maven-plugin:5.1.0.4751:sonar \
              -Dsonar.host.url=${host} \
              -Dsonar.token=\$SONAR_TOKEN \
              -Dsonar.projectKey=${key} \
              -Dsonar.projectName=${cfg.appName} \
              -Dsonar.projectVersion=${cfg.version ?: '1.0.0'} \
              -Dsonar.sources=src/main/java \
              -Dsonar.tests=src/test/java \
              -Dsonar.java.binaries=target/classes \
              -Dsonar.qualitygate.wait=false
        """

        // 门禁判定：sonar.forceAuthentication=true，必须带令牌，令牌当用户名、密码留空
        echo "[sonarScan] 查询质量门禁状态（projectKey=${key}）"
        String status = sh(
            script: """curl -sS -u "\$SONAR_TOKEN:" '${host}/api/qualitygates/project_status?projectKey=${key}'""",
            returnStdout: true
        ).trim()

        echo "[sonarScan] ${status}"

        if (!status.contains('"status"')) {
            error("[sonarScan] 质量门禁查询失败，返回内容不是预期 JSON：${status.take(400)}")
        }
        if (status.contains('"status":"ERROR"')) {
            error("[sonarScan] 质量门禁未通过（status=ERROR）：${status.take(600)}")
        }
        echo '[sonarScan] 质量门禁 OK'
    }
}
