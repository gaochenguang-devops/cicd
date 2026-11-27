#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
echo "=== shared-library vars/buildAndPushImage.groovy ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/3/repository/files/vars%2FbuildAndPushImage.groovy/raw?ref=main"
echo "=== demo-maven Jenkinsfile 里 registry 相关 ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/4/repository/files/Jenkinsfile/raw?ref=main" | grep -nE "192\.168|HARBOR|registry|jib" | head -20
echo "=== demo-maven pom.xml 里 registry 相关 ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "https://gitlab.corp.local/api/v4/projects/4/repository/files/pom.xml/raw?ref=main" | grep -nE "192\.168|registry|<to>|<image>" | head -20
