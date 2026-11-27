#!/bin/bash
set -uo pipefail
PAT=__GITLAB_PAT__
G=https://gitlab.corp.local/api/v4
python3 - <<'PY'
import json, urllib.request, ssl, base64

PAT="__GITLAB_PAT__"
G="https://gitlab.corp.local/api/v4"
ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE

def req(method, path, data=None, raw=False):
    url=G+path
    body=None; hdr={"PRIVATE-TOKEN":PAT}
    if data is not None:
        if raw: body=data; hdr["Content-Type"]="application/octet-stream"
        else: body=json.dumps(data).encode(); hdr["Content-Type"]="application/json"
    r=urllib.request.Request(url, data=body, headers=hdr, method=method)
    return urllib.request.urlopen(r, context=ctx, timeout=30).read().decode()

def get_file(proj, path, ref="main"):
    return req("GET", f"/projects/{proj}/repository/files/{urllib.parse.quote(path, safe='')}/raw?ref={ref}")

def put_file(proj, path, content, msg, branch="main"):
    return req("PUT", f"/projects/{proj}/repository/files/{urllib.parse.quote(path, safe='')}",
               {"branch":branch,"commit_message":msg,"content":content})

import urllib.parse

# ---- project 3: 共享库 ----
p="src/com/corp/platform/Defaults.groovy"
c=get_file(3,p)
c2=c.replace("192.168.200.12:30090","harbor.corp.local")
put_file(3,p,c2,"refactor: Harbor 地址改用 https 域名 harbor.corp.local")
print("  Defaults.groovy 已更新:", c2.count("harbor.corp.local"), "处")

p="vars/buildAndPushImage.groovy"
c=get_file(3,p)
c2=c.replace("192.168.200.12:30090","harbor.corp.local").replace("'http://${host}/v2","'https://${host}/v2")
c2=c2.replace("curl -sS -u","curl -sS -k -u")
put_file(3,p,c2,"refactor: Jib 推送走 https 域名，manifest 校验改 https（容器内无内部 CA，用 -k）")
print("  buildAndPushImage.groovy 已更新")

# ---- project 4: demo-maven ----
p="Jenkinsfile"
c=get_file(4,p)
c2=c.replace("HARBOR_HOST = '192.168.200.12:30090'","HARBOR_HOST = 'harbor.corp.local'")
put_file(4,p,c2,"refactor: Jenkins 推 Harbor 改走 https 域名")
print("  demo-maven Jenkinsfile 已更新")

p="pom.xml"
c=get_file(4,p)
c2=c.replace("192.168.200.12:30090","harbor.corp.local")
put_file(4,p,c2,"refactor: jib 基础镜像/目标镜像改用 https 域名")
print("  demo-maven pom.xml 已更新")
PY
echo "=== 复核 ==="
curl -s -k -H "PRIVATE-TOKEN: $PAT" "$G/projects/3/repository/files/vars%2FbuildAndPushImage.groovy/raw?ref=main" | grep -nE "harbor.corp.local|https://\\\$\{host\}|curl -sS" | head -6
curl -s -k -H "PRIVATE-TOKEN: $PAT" "$G/projects/4/repository/files/Jenkinsfile/raw?ref=main" | grep -n "HARBOR_HOST"
