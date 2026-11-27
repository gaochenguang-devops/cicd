#!/usr/bin/env bash
# 把 deploy 分支里两份 application.yaml 的 targetRevision 也改成 deploy（保持仓库内自洽）
set -uo pipefail
H="PRIVATE-TOKEN: __GITLAB_PAT__"
P="http://127.0.0.1/api/v4/projects/2"

for f in deploy/podinfo/application.yaml deploy/webapp/application.yaml; do
  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$f")
  echo "===== $f ====="
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" "$P/repository/files/$enc/raw?ref=deploy")
  if [ "$code" != "200" ]; then echo "  文件不在 deploy 分支（$code），跳过"; continue; fi
  python3 - "$f" "$enc" "$P" <<'PY'
import json, subprocess, sys, os
f, enc, P = sys.argv[1], sys.argv[2], sys.argv[3]
H = "PRIVATE-TOKEN: __GITLAB_PAT__"
raw = subprocess.run(["curl","-s","-H",H,f"{P}/repository/files/{enc}/raw?ref=deploy"],capture_output=True,text=True).stdout
if "targetRevision: deploy" in raw:
    print("  已经指向 deploy，无需改"); sys.exit(0)
new = raw.replace("targetRevision: main", "targetRevision: deploy")
payload = json.dumps({"branch":"deploy","content":new,"commit_message":f"deploy: {f} 指向 deploy 分支"})
open("/tmp/patch.json","w").write(payload)
r = subprocess.run(["curl","-s","-H",H,"-X","PUT","-H","Content-Type: application/json",
                    "--data","@/tmp/patch.json", f"{P}/repository/files/{enc}"],capture_output=True,text=True).stdout
print("  ->", r[:120])
PY
done

echo "===== 复核 ====="
for f in deploy/podinfo/application.yaml deploy/webapp/application.yaml; do
  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$f")
  echo "  $f: $(curl -s -H "$H" "$P/repository/files/$enc/raw?ref=deploy" | grep targetRevision | xargs)"
done
