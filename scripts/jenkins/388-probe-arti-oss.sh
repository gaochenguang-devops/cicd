#!/bin/bash
set -uo pipefail
A='http://192.168.200.12:30092/artifactory'
ADM='admin:__ARTIFACTORY_ADMIN_PASS__'
echo "=== 列出用户（看 OSS 是否连读都禁） ==="
curl -s -o /tmp/l.out -w 'list_users=%{http_code}\n' -u "$ADM" "$A/api/security/users"; head -c 200 /tmp/l.out; echo
echo "=== 列权限目标 ==="
curl -s -o /tmp/p.out -w 'list_perms=%{http_code}\n' -u "$ADM" "$A/api/security/permissions"; head -c 200 /tmp/p.out; echo
echo "=== 系统版本 / 许可 ==="
curl -s -u "$ADM" "$A/api/system/version"; echo
curl -s -u "$ADM" "$A/api/system/license" | head -c 300; echo
echo "=== 是否存在可用的非 admin 用户（匿名关否） ==="
curl -s -u "$ADM" "$A/api/system/configuration" 2>/dev/null | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin); print("  security keys:", list(d.get("security",{}).keys())[:8])
except Exception as e: print("  config api not available:", e)'
