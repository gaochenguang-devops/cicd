#!/usr/bin/env bash
set -uo pipefail
cat >/tmp/gitlab_init.rb <<'RUBY'
TOKEN = '__GITLAB_PAT__'
PW    = '__GITLAB_ROOT_PASS__'
u = User.find_by_username('root')
u.password = PW
u.password_confirmation = PW
u.save!
puts "ROOT_PASSWORD_OK=#{u.username}/#{PW}"

u.personal_access_tokens.where(name: 'argocd').destroy_all
t = u.personal_access_tokens.new(scopes: [:api], name: 'argocd', expires_at: 330.days.from_now)
if t.respond_to?(:set_token)
  t.set_token(TOKEN)
else
  t.token = TOKEN
end
if t.save
  puts "PAT_OK=#{TOKEN}"
else
  puts "PAT_ERR=#{t.errors.full_messages.join(', ')}"
end
RUBY
echo "=== 执行初始化 ==="
gitlab-rails runner /tmp/gitlab_init.rb 2>&1 | grep -E "ROOT_PASSWORD_OK|PAT_OK|PAT_ERR|Validation failed" | head -5

TOKEN=__GITLAB_PAT__
echo "=== API 验证 ==="
curl -sS -m 20 -H "PRIVATE-TOKEN: $TOKEN" "http://192.168.200.12/api/v4/user" | head -c 200; echo

echo "=== 创建项目 cicd-demo ==="
curl -sS -m 30 -X POST "http://192.168.200.12/api/v4/projects" \
  -H "PRIVATE-TOKEN: $TOKEN" \
  --data-urlencode "name=cicd-demo" --data-urlencode "path=cicd-demo" \
  --data-urlencode "description=GitLab -> ArgoCD 演示仓库" \
  --data-urlencode "visibility=internal" \
  --data-urlencode "initialize_with_readme=true" > /tmp/proj.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/proj.json'))
print("project:", d['path_with_namespace'], "| http:", d['http_url_to_repo'], "| web:", d['web_url']) if 'id' in d else print("ERR", d)
PY
