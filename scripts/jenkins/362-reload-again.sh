#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
POD=$(kubectl -n jenkins get pods -o jsonpath='{.items[0].metadata.name}')

echo "=== pod 内挂载的 jenkins.yaml 是否已更新 ==="
kubectl -n jenkins exec $POD -- bash -lc 'grep -c "harbor-jenkins-ci" /var/jenkins_home/casc_configs/jenkins.yaml 2>/dev/null || ls /var/jenkins_home/casc_configs 2>/dev/null || true'

echo "=== 等 30s 让 ConfigMap 卷同步 ==="
sleep 30

CK=/tmp/jck3; rm -f $CK
CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" -o /tmp/reload2.txt -w 'reload2=%{http_code}\n' -X POST "$J/configuration-as-code/reload"
sleep 8

echo "=== credentials 复查 ==="
curl -s -u "$AU" "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName]" ; echo

cat > /tmp/g2.groovy <<'EOF'
def inst = jenkins.model.Jenkins.get()
def store = inst.getExtension(jenkins.credentials.SystemCredentialsProvider).getStore()
store.getCredentials(com.cloudbees.plugins.credentials.domains.Domain.global()).each { c -> println "CRED: ${c.id} / ${c.class.simpleName}" }
def libs = inst.getDescriptorByType(org.jenkinsci.plugins.workflow.libs.GlobalLibraries.class).getLibraries()
libs.each { l -> println "LIB: ${l.name} default=${l.defaultVersion}" }
println "JOBS: " + inst.getJobNames()
EOF
code=$(curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" --data-urlencode "script@/tmp/g2.groovy" -o /tmp/sc2.txt -w '%{http_code}' -X POST "$J/scriptText")
echo "scriptText=$code"; head -c 800 /tmp/sc2.txt; echo
