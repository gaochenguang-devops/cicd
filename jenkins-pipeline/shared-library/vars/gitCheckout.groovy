#!/usr/bin/env groovy
/**
 * gitCheckout —— 统一代码拉取入口（分支 / commit / 浅克隆都在这里收口）
 *
 * 用法：
 *   gitCheckout(repo: 'http://192.168.200.12/root/demo-maven.git', branch: 'main')
 *   gitCheckout(repo: ..., branch: 'main', depth: 1)   // 大仓库加速
 */
def call(Map cfg) {
    if (!cfg.repo) {
        error('[gitCheckout] 缺少 repo 参数')
    }

    String branch = cfg.branch ?: 'main'
    Integer depth = (cfg.depth ?: 1) as Integer

    checkout([
        $class: 'GitSCM',
        branches: [[name: "*/${branch}"]],
        doGenerateSubmoduleConfigurations: false,
        extensions: [
            [$class: 'CloneOption', depth: depth, shallow: depth > 0, noTags: false],
            [$class: 'CleanBeforeCheckout']
        ],
        userRemoteConfigs: [[
            url: cfg.repo,
            credentialsId: cfg.credId ?: 'gitlab-pat'
        ]]
    ])

    String commit = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
    echo "[gitCheckout] ${cfg.repo} @ ${branch} -> ${commit}"
    return commit
}
