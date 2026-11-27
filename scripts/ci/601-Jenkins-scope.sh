#!/bin/bash
set -uo pipefail
J=http://192.168.200.12:30088
U='breakglass:__JENKINS_BREAKGLASS_PASS__'
CRUMB=$(curl -s -c /tmp/ck.txt -u "$U" "$J/crumbIssuer/api/json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["crumb"])')

echo "=== 给 Jenkins 任务打「独立任务」标注（方案 A） ==="
DESC='独立任务（方案A）：仅做 构建/质量门禁/制品推送，只读仓库、不写 deploy 分支，不参与发布写回。发布写回唯一归口 GitLab CI 的 update-manifest 阶段。'
curl -s -o /dev/null -w '  set-description=%{http_code}\n' -u "$U" -b /tmp/ck.txt -H "Jenkins-Crumb: $CRUMB" \
  --data-urlencode "description=$DESC" "$J/job/maven-demo-pipeline/submitDescription"
curl -s -u "$U" "$J/job/maven-demo-pipeline/api/json?tree=description" | python3 -c 'import json,sys;print("  当前描述:", json.load(sys.stdin)["description"])'

echo "=== Jenkins 凭据清单（确认没有 deploy 写权限凭据） ==="
curl -s -u "$U" -b /tmp/ck.txt "$J/credentials/store/system/domain/_/api/json?tree=credentials%5Bid,description%5D" \
 | python3 -c '
import json,sys
for c in json.load(sys.stdin)["credentials"]:
    print("    %-24s %s" % (c["id"], c.get("description","")))
'

echo "=== Jenkins 最近一次构建结论 ==="
curl -s -u "$U" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,result,duration" \
 | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  build #%s %s %ss" % (d["number"], d["result"], round(d["duration"]/1000,1)))'
