#!/bin/bash
set -uo pipefail
PAT='__GITLAB_PAT__'
push_one() {
  local dir=$1 name=$2
  cd "$dir"
  if [ ! -d .git ]; then
    git init -q -b main
    git config user.email "ci@corp.local"; git config user.name "cicd-bot"
  fi
  git add -A
  git -c user.email=ci@corp.local -c user.name=cicd-bot commit -q -m "init: $name" || echo "  (no changes)"
  git remote remove origin 2>/dev/null || true
  git remote add origin "http://root:__GITLAB_PAT__@192.168.200.12/root/${name}.git"
  git push -q -u origin main --force 2>&1 | tail -3
  echo "  pushed $(git rev-parse --short HEAD) -> root/${name} ($(git ls-files | wc -l) files)"
}
echo "=== demo-maven ==="; push_one /root/jenkins-src/demo-maven demo-maven
echo "=== shared-library ==="; push_one /root/jenkins-src/shared-library jenkins-shared-library
echo "=== gitlab 校验 ==="
curl -s -H "PRIVATE-TOKEN: $PAT" 'http://192.168.200.12/api/v4/projects/4/repository/tree?per_page=100' | python3 -c 'import sys,json;[print(" d4:",e["path"]) for e in json.load(sys.stdin)]'
curl -s -H "PRIVATE-TOKEN: $PAT" 'http://192.168.200.12/api/v4/projects/3/repository/tree?recursive=true&per_page=100' | python3 -c 'import sys,json;[print(" d3:",e["path"]) for e in json.load(sys.stdin)]'
