#!/bin/bash
set -uo pipefail
mkdir -p /root/grafana-dash
for id in 15757 1860 13332 13659; do
  code=$(curl -s -L -m 30 -o /root/grafana-dash/$id.json -w '%{http_code}' "https://grafana.com/api/dashboards/$id/revisions/latest/download")
  echo "=== id=$id http=$code size=$(stat -c%s /root/grafana-dash/$id.json 2>/dev/null)"
  python3 - "$id" <<'PY'
import json,sys
p=f"/root/grafana-dash/{sys.argv[1]}.json"
d=json.load(open(p))
print("  title:", d.get("title"), "| uid:", d.get("uid"), "| panels:", len(d.get("panels",[])))
print("  __inputs:", [i.get("name") for i in d.get("__inputs",[])])
print("  templating vars:", [t.get("name") for t in d.get("templating",{}).get("list",[])][:8])
PY
done

