#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
CK=/tmp/jck2; rm -f $CK

echo "=== raw credentials api ==="
curl -s -o /tmp/cred.txt -w 'http=%{http_code} size=%{size_download}\n' -u "$AU" "$J/credentials/store/system/domain/_/api/json"
head -c 300 /tmp/cred.txt; echo

CRUMB=$(curl -s -c $CK -u "$AU" "$J/crumbIssuer/api/json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
echo "=== script console: 列凭据 + 共享库 ==="
cat > /tmp/groovy.txt <<'EOF'
import jenkins.model.*
def inst = Jenkins.getInstanceOrInject()
def store = inst.getExtension(jenkins.credentials.SystemCredentialsProvider).getStore()
store.getCredentials(com.cloudbees.plugins.credentials.domains.Domain.global()).each { c -> println "CRED: ${c.id} / ${c.class.simpleName} / ${c.description}" }
def libs = inst.getDescriptorByType(org.jenkinsci.plugins.workflow.libs.GlobalLibraries.class).getLibraries()
libs.each { l -> println "LIB: ${l.name} default=${l.defaultVersion} retriever=${l.retriever.class.simpleName}" }
println "JOBS: " + inst.getJobNames()
EOF
code=$(curl -s -b $CK -u "$AU" -H "Jenkins-Crumb: $CRUMB" --data-urlencode "script@/tmp/groovy.txt" -o /tmp/sc.txt -w '%{http_code}' -X POST "$J/scriptText")
echo "scriptText http=$code"
head -c 800 /tmp/sc.txt; echo
