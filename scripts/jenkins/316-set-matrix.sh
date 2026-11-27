#!/usr/bin/env bash
# 把授权策略切到 matrix（platform-admins 管理员 / devops+developers 可构建），走 JCasC 热重载，不重启容器
set -u
BASE=http://127.0.0.1:30088
JAR=/tmp/jar_lead01.txt

echo "== 登录 lead01 =="
rm -f "$JAR" /tmp/l.html
curl -s -c "$JAR" -o /tmp/l.html "$BASE/login"
CRUMB=$(python3 - <<'PY'
import re
h=open('/tmp/l.html',encoding='utf-8',errors='ignore').read()
m=re.search(r'name="Jenkins-Crumb"[^>]*value="([^"]+)"',h)
print(m.group(1) if m else "")
PY
)
curl -s -b "$JAR" -c "$JAR" -o /dev/null -w '  login HTTP %{http_code}\n' \
  --data-urlencode "j_username=lead01" --data-urlencode "j_password=__LDAP_USER_INIT_PASS__" \
  --data-urlencode "Jenkins-Crumb=$CRUMB" --data "from=/&Submit=Sign+in" "$BASE/j_spring_security_check"
curl -s -b "$JAR" "$BASE/whoAmI/api/json"; echo

echo "== 触发 JCasC 重载 =="
CRUMB2=$(curl -s -b "$JAR" "$BASE/crumbIssuer/api/json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["crumb"])')
curl -s -b "$JAR" -X POST -H "Jenkins-Crumb: $CRUMB2" "$BASE/configuration-as-code/reload" -o /tmp/reload.json -w '  reload HTTP %{http_code}\n'
head -c 400 /tmp/reload.json; echo

echo "== 校验实际配置 =="
sudo sed -n '/authorizationStrategy/,/<\/authorizationStrategy>/p' /data/jenkins/config.xml | head -25
