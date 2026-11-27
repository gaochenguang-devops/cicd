#!/bin/bash
set -uo pipefail
K="kubectl -n jenkins"
POD=$($K get pods -o jsonpath='{.items[0].metadata.name}')
echo "=== java real ==="; $K exec $POD -- bash -lc 'ls -l $JAVA_HOME/bin/java 2>/dev/null; $JAVA_HOME/bin/java -version 2>&1 | head -3'
echo "=== home perms ==="; $K exec $POD -- bash -lc 'df -h /var/jenkins_home | tail -1; touch /var/jenkins_home/.wtest && echo writable && rm -f /var/jenkins_home/.wtest'
echo "=== casc full ==="; kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\.yaml}'
echo
echo "=== jenkins api with breakglass ==="
curl -s -o /dev/null -w 'whoami=%{http_code}\n' -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' http://192.168.200.12:30088/me/api/json
curl -s -u 'breakglass:__JENKINS_BREAKGLASS_PASS__' http://192.168.200.12:30088/whoAmI/api/json | head -c 400; echo
echo "=== gitlab projects ==="
curl -s -H 'PRIVATE-TOKEN: __GITLAB_PAT__' 'http://192.168.200.12/api/v4/projects?per_page=50&simple=true' | python3 -c 'import sys,json;[print(p["id"],p["path_with_namespace"]) for p in json.load(sys.stdin)]'
echo "=== harbor robot list (admin) ==="
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/robots?page_size=50' | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["name"],r.get("level")) for r in d]' 2>/dev/null || echo "robot-list-fail"
echo "=== sonar token/user ==="
curl -s -u 'sonaradmin:__SONAR_ADMIN_PASS__' 'http://192.168.200.12:30091/api/users/current' | head -c 300; echo
echo "=== artifactory repo ==="
curl -s -u 'admin:__ARTIFACTORY_ADMIN_PASS__' 'http://192.168.200.12:30092/artifactory/api/repositories?type=local' | head -c 400; echo
