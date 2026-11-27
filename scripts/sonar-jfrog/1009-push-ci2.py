#!/usr/bin/env python3
import json, urllib.request, urllib.parse

BASE = "http://192.168.200.12/api/v4/projects/root%2Fpodinfo"
TOKEN = "__GITLAB_PAT__"

content = open("/root/sonar-jfrog/ci-new/ci/publish-artifact.sh", encoding="utf-8").read()
url = BASE + "/repository/files/" + urllib.parse.quote("ci/publish-artifact.sh", safe="")
body = json.dumps({"branch": "main", "content": content,
                   "commit_message": "ci: 制品校验改为纯 sha256 对比，避免 sha256sum -c 格式问题"}).encode()
req = urllib.request.Request(url, data=body, method="PUT",
                             headers={"PRIVATE-TOKEN": TOKEN, "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req) as r:
        print("update", r.status)
except urllib.error.HTTPError as e:
    print("update", e.code, e.read().decode()[:300])

# 触发流水线
req2 = urllib.request.Request(BASE + "/pipeline?ref=main",
                              data=b"", method="POST",
                              headers={"PRIVATE-TOKEN": TOKEN})
try:
    with urllib.request.urlopen(req2) as r:
        d = json.loads(r.read())
        print("pipeline", d["id"], d["sha"][:8])
except urllib.error.HTTPError as e:
    print("pipeline", e.code, e.read().decode()[:300])
