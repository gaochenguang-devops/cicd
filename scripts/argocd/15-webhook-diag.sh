#!/usr/bin/env bash
cat >/tmp/urlcheck.rb <<'RUBY'
url = "http://192.168.200.12:30080/api/webhook"
begin
  Gitlab::UrlBlocker.validate!(url, schemes: ["http", "https"],
                               allow_local_requests: true,
                               deny_all_requests_except_allowed: false)
  puts "URL_OK"
rescue => e
  puts "ERR: #{e.class} #{e.message}"
end
puts "setting allow_local_requests=#{ApplicationSetting.current.allow_local_requests_from_web_hooks_and_services}"
puts "setting deny_all=#{ApplicationSetting.current.deny_all_requests_except_allowed}"
RUBY
gitlab-rails runner /tmp/urlcheck.rb 2>&1 | grep -E "URL_OK|ERR:|setting"

echo "=== 重新添加 webhook（带 token 参数）==="
TOKEN=__GITLAB_PAT__
curl -sS -m 20 -X POST "http://192.168.200.12/api/v4/projects/1/hooks" \
  -H "PRIVATE-TOKEN: $TOKEN" \
  -F "url=http://192.168.200.12:30080/api/webhook" \
  -F "push_events=true" \
  -F "enable_ssl_verification=false" > /tmp/hook.json 2>&1
head -c 400 /tmp/hook.json; echo
