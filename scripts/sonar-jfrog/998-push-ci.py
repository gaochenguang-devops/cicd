#!/usr/bin/env python3
import json, urllib.request, urllib.parse, os

BASE = "http://192.168.200.12/api/v4/projects/root%2Fpodinfo"
TOKEN = "__GITLAB_PAT__"

FILES = [
    ("/root/sonar-jfrog/ci-new/.gitlab-ci.yml", ".gitlab-ci.yml"),
    ("/root/sonar-jfrog/ci-new/sonar-project.properties", "sonar-project.properties"),
    ("/root/sonar-jfrog/ci-new/ci/publish-artifact.sh", "ci/publish-artifact.sh"),
]


def call(method, url, data=None):
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"PRIVATE-TOKEN": TOKEN,
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()[:200]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


def exists(path):
    url = BASE + "/repository/files/" + urllib.parse.quote(path, safe="") + "/raw?ref=main"
    req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": TOKEN})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status == 200
    except urllib.error.HTTPError:
        return False


for src, path in FILES:
    content = open(src, encoding="utf-8").read()
    for _ in range(5):  # 并发提交冲突时重试
        enc = urllib.parse.quote(path, safe="")
        if exists(path):
            st, msg = call("PUT", BASE + "/repository/files/" + enc,
                           {"branch": "main", "content": content,
                            "commit_message": "ci: 接入 Sonar 质量门禁与 Artifactory 制品发布"})
            act = "update"
        else:
            st, msg = call("POST", BASE + "/repository/files/" + enc,
                           {"branch": "main", "content": content,
                            "commit_message": "ci: 接入 Sonar 质量门禁与 Artifactory 制品发布"})
            act = "create"
        print(f"{act} {path} -> {st}")
        if st in (200, 201):
            break
        if st == 400 and "already exists" in msg:
            continue

# CI/CD 变量
VARS = [
    ("SONAR_TOKEN", "__SONAR_CI_TOKEN__", True),
    ("ARTIFACTORY_USER", "admin", False),
    ("ARTIFACTORY_PASS", "__ARTIFACTORY_ADMIN_PASS__", True),
]
for key, val, masked in VARS:
    st, msg = call("POST", BASE + "/variables",
                   {"key": key, "value": val, "masked": masked,
                    "protected": False, "variable_type": "env_var"})
    if st == 400 and "has already been taken" in msg:
        st, msg = call("PUT", BASE + "/variables/" + key,
                       {"key": key, "value": val, "masked": masked,
                        "protected": False, "variable_type": "env_var"})
        print(f"var {key} -> update {st}")
    else:
        print(f"var {key} -> {st}")
