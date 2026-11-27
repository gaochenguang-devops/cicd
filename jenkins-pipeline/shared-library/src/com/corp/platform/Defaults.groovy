/**
 * 平台构建约定的单一来源：所有共享库步骤都从这里取默认值，
 * Jenkinsfile 只需要传少量参数。
 */
package com.corp.platform

class Defaults implements Serializable {

    static final String MAVEN_HOME = '/var/jenkins_home/tools/apache-maven-3.9.9'

    static final String HARBOR_HOST = '192.168.200.12:30090'
    static final String HARBOR_PROJECT = 'apps'
    static final String BASE_IMAGE = '192.168.200.12:30090/library/eclipse-temurin:21-jre'
    static final String HARBOR_CRED_ID = 'harbor-jenkins-ci'

    static final String SONAR_HOST = 'http://192.168.200.12:30091'
    static final String SONAR_CRED_ID = 'sonar-token'

    static final String ARTIFACTORY_HOST = 'http://192.168.200.12:30092'
    static final String ARTIFACTORY_REPO = 'build-artifacts'
    static final String ARTIFACTORY_CRED_ID = 'artifactory-admin'

    static final String GIT_CRED_ID = 'gitlab-pat'

    /** 拼接镜像全名：192.168.200.12:30090/apps/<app>:<version> */
    static String image(Map cfg) {
        String host = cfg.harborHost ?: HARBOR_HOST
        String project = cfg.harborProject ?: HARBOR_PROJECT
        return "${host}/${project}/${cfg.appName}:${cfg.version}"
    }

    /** 制品在 Artifactory 的第二段路径：<app>/<branch>/<version>/ */
    static String artifactPath(Map cfg) {
        String branch = (cfg.branch ?: 'main').replaceAll('/', '_')
        return "${cfg.appName}/${branch}/${cfg.version}"
    }

    /** mvn 可执行文件；PATH 由 Jenkinsfile 的 environment 段补齐 */
    static String mvn() {
        return "${MAVEN_HOME}/bin/mvn"
    }
}
