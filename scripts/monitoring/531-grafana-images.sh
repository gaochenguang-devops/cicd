#!/bin/bash
set -uo pipefail
U='admin:__HARBOR_ADMIN_PASS__'
for r in grafana blackbox-exporter; do
  echo "=== library/$r 现有 tag ==="
  curl -s -k -u "$U" "https://harbor.corp.local/api/v2.0/projects/library/repositories/$r/artifacts?page_size=10&with_tag=true" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d[:6]: print("  ", [t["name"] for t in (a.get("tags") or [])], a.get("size"))
'
done
echo "=== grafana.com dashboard 下载端点试探 ==="
for id in 1860 15757; do
  for u in "https://grafana.com/api/dashboards/$id/revisions/latest/download" "https://grafana.com/api/dashboards/$id"; do
    code=$(curl -s -o /tmp/gd_$id.json -w '%{http_code}' -L -m 25 "$u")
    echo "  id=$id $u -> $code  size=$(stat -c%s /tmp/gd_$id.json 2>/dev/null)"
  done
done
head -c 200 /tmp/gd_1860.json 2>/dev/null; echo
