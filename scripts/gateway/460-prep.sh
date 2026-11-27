#!/bin/bash
# 阶段一：前置准备（不改变任何对外 URL，切换前后都安全）
set -uo pipefail
BK=$(cat /tmp/exturl-backup-dir)
CA=/root/gateway-tls/ca.crt
HOSTS_LINE="192.168.200.210 gitlab.corp.local jenkins.corp.local harbor.corp.local sonar.corp.local artifactory.corp.local argocd.corp.local keycloak.corp.local ldapadmin.corp.local podinfo.corp.local webapp.corp.local prometheus.corp.local alertmanager.corp.local"

echo "===== 1. 宿主 hosts + 系统 CA 信任 ====="
grep -q "gitlab.corp.local" /etc/hosts || echo "$HOSTS_LINE" >> /etc/hosts
grep -c corp.local /etc/hosts
mkdir -p /etc/pki/ca-trust/source/anchors
cp -f $CA /etc/pki/ca-trust/source/anchors/corp-internal-ca.crt
update-ca-trust 2>&1 | tail -2
echo "  curl 测试（走系统信任，不带 -k）："
curl -s -o /dev/null -w "  gitlab.corp.local -> %{http_code}\n" https://gitlab.corp.local/ -m 10

echo "===== 2. GitLab trusted-certs（Rails 调 Keycloak 用） ====="
mkdir -p /etc/gitlab/trusted-certs
cp -f $CA /etc/gitlab/trusted-certs/corp-internal-ca.crt
ls -l /etc/gitlab/trusted-certs/

echo "===== 3. CoreDNS：新增 corp.local 权威区（12 域名 → VIP） ====="
cat >/tmp/corp.hosts <<EOF
$HOSTS_LINE
EOF
kubectl -n kube-system create cm coredns-corp-hosts --from-file=corp.hosts=/tmp/corp.hosts --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/Corefile.orig
cp /tmp/Corefile.orig $BK/Corefile.bak
python3 - <<'PY'
p="/tmp/Corefile.orig"
s=open(p).read()
if "corp.local:53" not in s:
    s += """
corp.local:53 {
    errors
    hosts /etc/coredns/corp.hosts {
        ttl 30
    }
}
"""
open("/tmp/Corefile.new","w").write(s)
PY
kubectl -n kube-system create cm coredns --from-file=Corefile=/tmp/Corefile.new --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kube-system patch deploy coredns --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"corp-hosts","configMap":{"name":"coredns-corp-hosts","defaultMode":420}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"corp-hosts","mountPath":"/etc/coredns/corp.hosts","subPath":"corp.hosts","readOnly":true}}
]'
kubectl -n kube-system rollout status deploy/coredns --timeout=120s | tail -1
sleep 3
echo "  --- 集群内解析验证（从 runner 侧任意 Pod） ---"
kubectl -n jenkins exec deploy/jenkins -- getent hosts keycloak.corp.local gitlab.corp.local 2>&1 | head -4

echo "===== 4. Jenkins JVM 信任库（cacerts + 内部 CA） ====="
kubectl -n jenkins cp $CA deploy/jenkins:/tmp/corp-ca.crt -c jenkins
kubectl -n jenkins exec deploy/jenkins -c jenkins -- sh -c '
cp $JAVA_HOME/lib/security/cacerts /tmp/cacerts-corp
$JAVA_HOME/bin/keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca \
  -file /tmp/corp-ca.crt -keystore /tmp/cacerts-corp -storepass changeit 2>&1 | tail -2
ls -l /tmp/cacerts-corp'
kubectl -n jenkins cp deploy/jenkins:/tmp/cacerts-corp /tmp/cacerts-jenkins -c jenkins
kubectl -n jenkins create secret generic jenkins-java-cacerts --from-file=cacerts=/tmp/cacerts-jenkins --dry-run=client -o yaml | kubectl apply -f -
kubectl -n jenkins patch deploy jenkins --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"secretName":"jenkins-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]'
echo "  Jenkins 稍后统一重启（阶段三）"

echo "===== 5. Sonar JVM 信任库 ====="
kubectl -n sonar cp $CA deploy/sonarqube:/tmp/corp-ca.crt -c sonarqube
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c '
cp $JAVA_HOME/lib/security/cacerts /tmp/cacerts-corp
$JAVA_HOME/bin/keytool -importcert -noprompt -trustcacerts -alias corp-internal-ca \
  -file /tmp/corp-ca.crt -keystore /tmp/cacerts-corp -storepass changeit 2>&1 | tail -2'
kubectl -n sonar cp deploy/sonarqube:/tmp/cacerts-corp /tmp/cacerts-sonar -c sonarqube
kubectl -n sonar create secret generic sonar-java-cacerts --from-file=cacerts=/tmp/cacerts-sonar --dry-run=client -o yaml | kubectl apply -f -
kubectl -n sonar patch deploy sonarqube --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"java-cacerts","secret":{"secretName":"sonar-java-cacerts"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"java-cacerts","mountPath":"/opt/java/openjdk/lib/security/cacerts","subPath":"cacerts","readOnly":true}}
]'
echo "  Sonar 稍后统一重启（阶段三）"

echo "===== 6. 集群内到 VIP 的可达性（Keycloak 站点，当前还是旧 issuer） ====="
kubectl -n jenkins exec deploy/jenkins -- curl -sk -o /dev/null -w "  https://keycloak.corp.local -> %{http_code}\n" https://keycloak.corp.local/realms/corp/.well-known/openid-configuration -m 10
echo "===== 阶段一完成 ====="
