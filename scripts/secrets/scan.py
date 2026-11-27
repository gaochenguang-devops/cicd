#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
仓库泄露扫描器（凭据 + 内部信息），上传 GitHub 前跑一遍。

用法：
  python scripts/secrets/scan.py                # 扫全仓
  python scripts/secrets/scan.py docs           # 只扫某个目录
  python scripts/secrets/scan.py --only secret  # 只看凭据类（默认两类都看）
  python scripts/secrets/scan.py --verbose      # 打印每一条命中（默认只打前几条）

判定：
  SECRET    真凭据（.env 里的值以原形/URL 编码/转义形态出现，或命中私钥、JWT、云厂商 key 等模式）
  INTERNAL  内部架构信息（内网 IP、内部域名、机器人名、账号名、真实人名），不是口令但会暴露内网
  OK        模板占位（<REPLACE_ME> / ${VAR} / __VAR__ / xxxx / … 遮罩），不计入告警

退出码：0 干净（可能只有 INTERNAL）；1 有 SECRET；2 环境错误。
"""

import argparse
import base64
import os
import re
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

TEXT_EXT = {".md", ".yaml", ".yml", ".sh", ".py", ".json", ".txt", ".conf",
            ".groovy", ".ps1", ".rb", ".yml", ".Jenkinsfile", ""}

SECRET_PATTERNS = [
    ("私钥块", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("kubeconfig", re.compile(r"(?:certificate-authority-data|client-key-data):\s*[A-Za-z0-9+/=]{20,}")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}")),
    ("AWS AK", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("钉钉 token", re.compile(r"access_token=[0-9a-f]{32,}")),
    ("钉钉加签密钥", re.compile(r"SEC[0-9a-f]{32,}")),
    ("GitLab PAT", re.compile(r"glpat-[A-Za-z0-9_-]{15,}")),
    ("Sonar token", re.compile(r"squ_[0-9a-f]{30,}")),
    ("URL 带口令", re.compile(r"(?:https?|ldap|ssh)://[^\s:/@\"']+:[^\s:/@\"']{3,}@")),
    ("Basic Auth 明文", re.compile(r"-u\s+\"[A-Za-z0-9._-]+:[^\s\"'$<{]{4,}\"|-u\s+[A-Za-z0-9._-]+:[^\s\"'$<{\u4e00-\u9fff]{4,}")),
    ("赋值型口令", re.compile(r"(?i)\b(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s\"'$,]{6,}")),
]

# 看起来就不是秘密的值：占位、变量名、代码表达式、纯模板
WEAK = re.compile(
    r"(?:"
    r"<.*?>|"                      # <TOKEN>
    r"\$\{.*?\}|__[A-Z0-9_]+__|"   # 占位符
    r"[A-Z][A-Z0-9_]{2,}|"         # TOKEN / SSH_PASSWORD 这类变量名
    r"[A-Za-z_][\w.]*\(.*|"         # os.environ.get(...)
    r"[A-Za-z_]\w*\[.*|"           # headers[...]
    r".*REPLACE.*|.*xxxx.*|.*XXXX.*|.*…|.*\.\.\."
    r")"
)

# 允许出现在文档里的弱口令/示例词
BENIGN_WORDS = {"password", "passwd", "secret", "token", "changeme", "admin", "root",
                "redacted", "masked", "hidden", "密码", "口令", "verification", "failed", "error", "required"}

INTERNAL_PATTERNS = [
    ("内网 IP", re.compile(r"\b(?:10|172|192)\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")),
    ("内部域名", re.compile(r"\b[a-z0-9-]+\.corp\.local\b")),
]

MASK_HINTS = ("<REPLACE_ME>", "<TOKEN>", "${", "__", "xxxx", "XXXX", "…", "...",
              "REPLACE", "REPLACE_ME", "your", "example", "$VAR", "****")


def load_env():
    path = os.path.join(ROOT, ".env")
    vals = {}
    if not os.path.isfile(path):
        return vals
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            v = v.strip().strip('"').strip("'")
            if (len(v) >= 8 and v.lower() not in ("admin", "root", "password", "true")
                    and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k.strip())):
                vals[k.strip()] = v
    return vals


def variants(v):
    """同一个凭据可能出现的几种形态。"""
    out = {v}
    out.add(urllib.parse.quote(v, safe=""))
    out.add(urllib.parse.quote_plus(v))
    out.add(v.replace("!", "\\!").replace("$", "\\$"))
    b = base64.b64encode(v.encode()).decode()
    out.add(b)
    return {x for x in out if len(x) >= 4}


def walk(targets):
    for t in targets:
        p = t if os.path.isabs(t) else os.path.join(ROOT, t)
        if os.path.isfile(p):
            yield p
            continue
        for dp, dns, fns in os.walk(p):
            dns[:] = [d for d in dns if d != ".git" and d not in ("node_modules", "__pycache__", ".venv")]
            for fn in fns:
                fp = os.path.join(dp, fn)
                if os.path.splitext(fn)[1].lower() in TEXT_EXT:
                    yield fp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="*", help="目录或文件，默认全仓")
    ap.add_argument("--only", choices=["secret", "internal"])
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--show", type=int, default=6, help="每类最多展示几条")
    args = ap.parse_args()

    env = load_env()
    env_map = {}
    skip_suffix = ("_USER", "_HOST", "_PORT", "_DN", "_NAME")
    for k, v in env.items():
        # 主机/端口/用户名/DN 是连接信息，不是凭据，不做真值匹配
        if k.endswith(skip_suffix) or k.startswith("SSH_"):
            continue
        for var in variants(v):
            env_map.setdefault(var, k)

    counts = {"SECRET": 0, "INTERNAL": 0}
    samples = {"SECRET": [], "INTERNAL": []}
    by_file = {"SECRET": {}, "INTERNAL": {}}
    env_hits = []

    for fp in walk(args.targets or [ROOT]):
        rel = os.path.relpath(fp, ROOT).replace("\\", "/")
        if rel == ".env":
            continue
        try:
            with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if not s or (s.startswith("#") and "password" not in s.lower()):
                pass
            # 1) 已知真值（含编码/转义形态）
            for var in variants_map_hit(line, env_map):
                key = env_map[var]
                counts["SECRET"] += 1
                by_file["SECRET"][rel] = by_file["SECRET"].get(rel, 0) + 1
                samples["SECRET"].append("%s:%d  命中 .env 中的 %s（值已隐藏）" % (rel, i, key))
            # 2) 通用模式
            for label, rx in SECRET_PATTERNS:
                m = rx.search(line)
                if not m:
                    continue
                hit = m.group(0)
                if is_weak(hit, label):
                    continue
                counts["SECRET"] += 1
                by_file["SECRET"][rel] = by_file["SECRET"].get(rel, 0) + 1
                samples["SECRET"].append("%s:%d  %s: %s" % (rel, i, label, mask(hit)))
            if args.only == "secret":
                continue
            for label, rx in INTERNAL_PATTERNS:
                if rx.search(line):
                    counts["INTERNAL"] += 1
                    by_file["INTERNAL"][rel] = by_file["INTERNAL"].get(rel, 0) + 1
                    if len(samples["INTERNAL"]) < args.show * 3:
                        samples["INTERNAL"].append("%s:%d  %s  %s" % (rel, i, label, s[:90]))

    print("=== 凭据类（SECRET）===")
    if counts["SECRET"]:
        for s in (samples["SECRET"] if args.verbose else samples["SECRET"][: args.show]):
            print("  !", s)
        print("  共 %d 处，涉及 %d 个文件" % (counts["SECRET"], len(by_file["SECRET"])))
    else:
        print("  0 处 —— 仓库内没有 .env 真值或明文口令形态")

    if args.only != "secret":
        print("\n=== 内部信息（INTERNAL，不是口令，决定仓库是否设 Private）===")
        if counts["INTERNAL"]:
            for s in (samples["INTERNAL"] if args.verbose else samples["INTERNAL"][: args.show]):
                print("  -", s)
            print("  共 %d 处，涉及 %d 个文件（地址/域名占绝大多数，属有意保留的内部文档）"
                  % (counts["INTERNAL"], len(by_file["INTERNAL"])))
        else:
            print("  0 处")

    return 1 if counts["SECRET"] else 0


def variants_map_hit(line, env_map):
    found = []
    for var in env_map:
        if var in line:
            found.append(var)
    return found


def is_weak(hit, label):
    if "<" in hit or "{" in hit or "%23" in hit:
        return True
    if any(h in hit for h in MASK_HINTS):
        return True
    if label == "赋值型口令":
        value = re.split(r"[:=]", hit, maxsplit=1)[-1].strip().strip('"').strip("'")
        if not value or len(value) < 6:
            return True
        if value.lower() in BENIGN_WORDS:
            return True
        if " " in value or value.count("/") == 1 and re.match(r"^[a-z0-9._/-]+$", value):
            return True   # "token verification failed"、Secret 资源名 argocd/gitlab-repo-creds
        if WEAK.match(value):
            return True
    return False


def mask(s):
    if len(s) <= 8:
        return "***"
    return s[:4] + "***" + s[-4:]


if __name__ == "__main__":
    sys.exit(main())
