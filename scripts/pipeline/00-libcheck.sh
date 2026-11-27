#!/usr/bin/env bash
set -uo pipefail
source /root/cicd-test/lib-test.sh
get_token
echo "token len=${#TOKEN}"
echo "app sync=$(APP_SYNC demo-app) health=$(APP_HEALTH demo-app) rev=$(APP_REV demo-app | head -c 7)"
echo "repo HEAD=$(cd $REPO_DIR && git rev-parse HEAD | head -c 7)"
echo "autoSync=$(APP_FIELD demo-app '.spec.syncPolicy')"
echo "clusters=$(api_get /api/v1/clusters | jq -r '.[].server')"
echo "webhooks=$(curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "$GL/api/v4/projects/1/hooks" | jq -r '.[] | "\(.id) \(.url) push=\(.push_events)"')"
echo "--- deployment in cluster ---"
kubectl -n demo get deploy demo-nginx -o jsonpath='{.spec.replicas}{" pods="}' 2>/dev/null; kubectl -n demo get pods --no-headers 2>/dev/null | wc -l
