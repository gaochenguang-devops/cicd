#!/bin/bash
set -uo pipefail
echo "=== 磁盘余量 ==="
df -h / | tail -1

push_one() {
  local src="$1" dst="$2"
  echo "--- $src -> $dst"
  podman pull -q "$src" >/dev/null 2>&1 || { echo "  pull 失败: $src"; return 1; }
  podman tag "$src" "$dst"
  echo '__HARBOR_ADMIN_PASS__' | podman login -u admin --password-stdin harbor.corp.local >/dev/null 2>&1
  podman push -q "$dst" >/dev/null 2>&1 && echo "  pushed" || echo "  push 失败"
}

for tag in 11.3.0 11.2.0 11.1.0; do
  if podman pull -q "docker.m.daocloud.io/grafana/grafana:$tag" >/dev/null 2>&1; then
    echo "grafana 可用 tag: $tag"
    podman tag "docker.m.daocloud.io/grafana/grafana:$tag" "harbor.corp.local/library/grafana:$tag"
    echo '__HARBOR_ADMIN_PASS__' | podman login -u admin --password-stdin harbor.corp.local >/dev/null 2>&1
    podman push -q "harbor.corp.local/library/grafana:$tag" >/dev/null 2>&1 && echo "  grafana:$tag pushed"
    break
  fi
done

for tag in v0.25.0 v0.24.0; do
  if podman pull -q "docker.m.daocloud.io/prom/blackbox-exporter:$tag" >/dev/null 2>&1; then
    podman tag "docker.m.daocloud.io/prom/blackbox-exporter:$tag" "harbor.corp.local/library/blackbox-exporter:$tag"
    podman push -q "harbor.corp.local/library/blackbox-exporter:$tag" >/dev/null 2>&1 && echo "  blackbox-exporter:$tag pushed"
    break
  fi
done

echo "=== Harbor 复查 ==="
for r in grafana blackbox-exporter; do
  echo "--- $r"
  curl -s -k -u admin:__HARBOR_ADMIN_PASS__ "https://harbor.corp.local/api/v2.0/projects/library/repositories/$r/artifacts?page_size=10&with_tag=true" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for a in d[:5]: print("  ", [t["name"] for t in (a.get("tags") or [])], round((a.get("size") or 0)/1e6,1),"MB")
'
done
dpkg -k 2>/dev/null; df -h / | tail -1
