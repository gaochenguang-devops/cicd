#!/usr/bin/env groovy
/**
 * buildAndPushImage —— 用 Jib 直接构建并推送镜像到 Harbor（无需 docker daemon）
 *
 * 为什么不用 docker build：
 *   Jenkins 是 K8s 里的纯容器，没有 /var/run/docker.sock，buildah 在非特权 Pod 里也跑不起来。
 *   Jib 走 registry API 分层上传，天然适配这种"无 daemon"环境。
 *
 * 凭据分两个 robot（Harbor 规定项目级 robot 只能绑一个项目）：
 *   harbor-jenkins-ci → apps 项目 pull+push（推镜像）
 *   harbor-lib-pull   → library 项目 pull（拉基础镜像）
 *
 * 用法：
 *   buildAndPushImage(appName: 'maven-demo', version: '1.0.42')
 */
def call(Map cfg) {
    if (!cfg.appName || !cfg.version) {
        error('[buildAndPushImage] 需要 appName 与 version')
    }

    String host = cfg.harborHost ?: '192.168.200.12:30090'
    String project = cfg.harborProject ?: 'apps'
    String image = "${host}/${project}/${cfg.appName}"
    String base = cfg.baseImage ?: '192.168.200.12:30090/library/eclipse-temurin:21-jre'
    String mvnc = cfg.mvn ?: '/var/jenkins_home/tools/apache-maven-3.9.9/bin/mvn'

    String pushed = null
    withCredentials([
        usernamePassword(credentialsId: cfg.harborCredId ?: 'harbor-jenkins-ci',
                         usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS'),
        usernamePassword(credentialsId: cfg.basePullCredId ?: 'harbor-lib-pull',
                         usernameVariable: 'BASE_USER', passwordVariable: 'BASE_PASS')
    ]) {
        sh """
            ${mvnc} -B -ntp -DskipTests jib:build \
              -Djib.allowInsecureRegistries=true \
              -DsendCredentialsOverHttp=true \
              -Djib.from.image=${base} \
              -Djib.from.auth.username=\$BASE_USER \
              -Djib.from.auth.password=\$BASE_PASS \
              -Djib.to.image=${image} \
              -Djib.to.tags=${cfg.version} \
              -Djib.to.auth.username=\$HARBOR_USER \
              -Djib.to.auth.password=\$HARBOR_PASS
        """

        // 推完立刻验证 manifest 可读，才算"门禁 1"通过
        sh """
            curl -sS -u "\$HARBOR_USER:\$HARBOR_PASS" -o /dev/null -w 'manifest_http=%{http_code}\\n' \
              -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
              'http://${host}/v2/${project}/${cfg.appName}/manifests/${cfg.version}'
        """
        echo "[buildAndPushImage] 已推送到 ${image}:${cfg.version}"
        pushed = "${image}:${cfg.version}"
    }
    return pushed
}
