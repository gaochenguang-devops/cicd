#!/usr/bin/env python3
# 把凭据与全局共享库合并进现有 JCasC（jenkins.yaml），保留原有 OIDC 配置
import subprocess, sys

def sh(cmd):
    return subprocess.check_output(cmd, shell=True).decode()

cur = sh("kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\\.yaml}'")

CREDS = '''  credentials:
    system:
      domainCredentials:
        - credentials:
            - usernamePassword:
                scope: GLOBAL
                id: gitlab-pat
                username: "root"
                password: "__GITLAB_PAT__"
                description: "GitLab PAT（拉私有仓库）"
            - usernamePassword:
                scope: GLOBAL
                id: harbor-jenkins-ci
                username: "robot$apps+jenkins-ci"
                password: "__HARBOR_ROBOT_JENKINS_SECRET__"
                description: "Harbor apps 项目推送（robot）"
            - usernamePassword:
                scope: GLOBAL
                id: harbor-lib-pull
                username: "robot$library+jenkins-lib-pull"
                password: "__HARBOR_ROBOT_LIB_SECRET__"
                description: "Harbor library 拉基础镜像（robot）"
            - string:
                scope: GLOBAL
                id: sonar-token
                secret: "__SONAR_CI_TOKEN__"
                description: "Sonar CI 令牌"
            - usernamePassword:
                scope: GLOBAL
                id: artifactory-admin
                username: "admin"
                password: "__ARTIFACTORY_ADMIN_PASS__"
                description: "Artifactory 制品上传"
'''

LIB = '''  globalLibraries:
    libraries:
      - name: "platform-lib"
        defaultVersion: "main"
        implicit: false
        allowVersionOverride: true
        retriever:
          modernSCM:
            scm:
              git:
                remote: "http://192.168.200.12/root/jenkins-shared-library.git"
                credentialsId: "gitlab-pat"
'''

if 'id: harbor-jenkins-ci' in cur and 'name: "platform-lib"' in cur:
    print("[skip] credentials/library 已存在")
    sys.exit(0)

lines = cur.splitlines()
out = []
for line in lines:
    if line.startswith('  securityRealm:') and 'id: gitlab-pat' not in cur:
        out.append(CREDS.rstrip('\n'))
    out.append(line)
new = '\n'.join(out) + '\n'

# 在 unclassified 下插入 globalLibraries（紧跟 unclassified: 之后）
lines = new.splitlines()
out = []
for line in lines:
    out.append(line)
    if line.strip() == 'unclassified:' and 'globalLibraries' not in new:
        out.append(LIB.rstrip('\n'))
new = '\n'.join(out) + '\n'

open('/tmp/jenkins-casc.yaml', 'w').write(new)
print(sh("kubectl -n jenkins create configmap jenkins-casc --from-file=jenkins.yaml=/tmp/jenkins-casc.yaml --dry-run=client -o yaml | kubectl apply -f -"))
print("---- 新配置片段 ----")
print(new[:1200])
