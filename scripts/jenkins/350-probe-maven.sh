#!/bin/bash
set -uo pipefail
K="kubectl -n jenkins"
echo "=== pods ==="; $K get pods -o wide
POD=$($K get pods -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -z "$POD" ] && POD=$($K get pods -o jsonpath='{.items[0].metadata.name}')
echo "POD=$POD"
echo "=== java ==="; $K exec $POD -- bash -lc 'java -version 2>&1; echo JAVA_HOME=$JAVA_HOME'
echo "=== mvn ==="; $K exec $POD -- bash -lc 'which mvn || echo no-mvn'
echo "=== tools ==="; $K exec $POD -- bash -lc 'which git curl unzip tar docker buildah kaniko 2>/dev/null; echo ---; id; ls -la /data | head'
echo "=== egress maven central ==="; $K exec $POD -- bash -lc "curl -s -o /dev/null -w 'central=%{http_code}\n' --max-time 8 https://repo1.maven.org/maven2/ || echo central-fail"
echo "=== aliyun mirror ==="; $K exec $POD -- bash -lc "curl -s -o /dev/null -w 'aliyun=%{http_code}\n' --max-time 8 https://maven.aliyun.com/repository/public/ || echo aliyun-fail"
echo "=== harbor ==="; $K exec $POD -- bash -lc "curl -s -o /dev/null -w 'harbor=%{http_code}\n' --max-time 5 http://192.168.200.12:30090/v2/"
echo "=== artifactory ==="; $K exec $POD -- bash -lc "curl -s -o /dev/null -w 'arti=%{http_code}\n' --max-time 5 http://192.168.200.12:30092/artifactory/api/system/ping"
echo "=== plugins (subset) ==="; $K exec $POD -- bash -lc 'ls /var/jenkins_home/plugins 2>/dev/null | sed "s/.jpi//;s/.hpi//" | sort | tr "\n" " "'
echo
echo "=== job/creds ==="
$K exec $POD -- bash -lc 'ls /var/jenkins_home/jobs 2>/dev/null || echo no-jobs'
echo "=== casc cm ==="; kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data}' | head -c 200; echo
echo "=== nodePort svc ==="; kubectl -n jenkins get svc
