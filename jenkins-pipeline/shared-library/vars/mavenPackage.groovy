#!/usr/bin/env groovy
/**
 * mavenPackage —— 编译 + 单测 + 打包（失败即中断流水线）
 *
 * 用法：
 *   mavenPackage(appName: 'maven-demo', version: '1.0.42')
 * 产出：
 *   target/maven-demo.jar（由 pom 的 finalName 决定），并归档到 Jenkins 构建产物
 */
def call(Map cfg) {
    if (!cfg.appName) {
        error('[mavenPackage] 缺少必填参数 appName')
    }

    sh """
        ${cfg.mvn ?: '/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn'} -B -ntp clean package
    """

    // 归档 jar；单测报告只留在日志里（未装 junit 插件，不用 junit 步骤）
    archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: false

    echo "[mavenPackage] 打包完成：target/${cfg.appName}.jar (version ${cfg.version})"
    return "target/${cfg.appName}.jar"
}
