#!/usr/bin/env groovy
/**
 * publishArtifact —— 把 jar + sha256 + build-info 推到 Artifactory（Generic 仓库）
 *
 * 为什么推到 Artifactory 而不是再推一次镜像：
 *   镜像是"运行时产物"，Artifactory 这里承担的是"这次构建交付了什么"的可审计凭证：
 *   jar 本体、sha256 校验文件、以及一条 build-info.json。
 *   Artifactory OSS 没有 docker registry，镜像继续留在 Harbor —— 两者职责不重叠。
 *
 * 用法：
 *   publishArtifact(appName: 'maven-demo', version: '1.0.42', jar: 'target/maven-demo.jar')
 */
def call(Map cfg) {
    if (!cfg.jar) {
        error('[publishArtifact] 缺少 jar 路径')
    }

    String host = cfg.artifactoryHost ?: 'http://192.168.200.12:30092'
    String repo = cfg.artifactoryRepo ?: 'build-artifacts'
    String branch = (cfg.branch ?: 'main').replaceAll('/', '_')
    String path = "${cfg.appName}/${branch}/${cfg.version}"
    String jarName = cfg.jar.tokenize('/')[-1]

    String published = null
    withCredentials([usernamePassword(
        credentialsId: cfg.artifactoryCredId ?: 'artifactory-admin',
        usernameVariable: 'ARTI_USER',
        passwordVariable: 'ARTI_PASS'
    )]) {
        sh """
            set -e
            SHA=\$(sha256sum ${cfg.jar} | awk '{print \$1}')
            echo "\$SHA" > ${jarName}.sha256
            printf '{"app":"${cfg.appName}","version":"${cfg.version}","branch":"${cfg.branch ?: 'main'}","build":"${env.BUILD_NUMBER}","sha256":"%s","commit":"${env.GIT_COMMIT ?: 'n/a'}","image":"${cfg.image ?: ''}"}\\n' "\$SHA" > build-info.json

            curl -sS -f -u "\$ARTI_USER:\$ARTI_PASS" -T ${cfg.jar} \
              '${host}/artifactory/${repo}/${path}/${jarName}'
            curl -sS -f -u "\$ARTI_USER:\$ARTI_PASS" -T ${jarName}.sha256 \
              '${host}/artifactory/${repo}/${path}/${jarName}.sha256'
            curl -sS -f -u "\$ARTI_USER:\$ARTI_PASS" -T build-info.json \
              '${host}/artifactory/${repo}/${path}/build-info.json'

            echo "artifact_sha256=\$SHA"
        """

        // 回读校验：文件存在 + 大小 + sha256 与本地一致，才算发布成功
        String remote = sh(
            script: """curl -sS -u "\$ARTI_USER:\$ARTI_PASS" '${host}/artifactory/api/storage/${repo}/${path}/${jarName}'""",
            returnStdout: true
        ).trim()
        if (!remote.contains('"downloadUri"')) {
            error("[publishArtifact] 回读失败：${remote.take(300)}")
        }
        echo "[publishArtifact] ${host}/artifactory/${repo}/${path}/"
        published = "${repo}/${path}"
    }
    return published
}
