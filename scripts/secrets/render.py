#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨平台凭据渲染器（Windows / Linux / macOS 通用，Windows 上用这个，不要用 render.sh）。

占位约定：
  *.sh / *.py  →  __VAR__        （避免单引号内 ${} 不展开的问题）
  *.yaml / *.md →  ${VAR}        （envsubst / shell / 文档统一风格）

用法：
  # 渲染单个脚本到 stdout（Linux 上可直接管道给 bash）
  python scripts/secrets/render.py scripts/monitoring/705-final-verify.sh
  python scripts/secrets/render.py scripts/xx.sh > /tmp/x.sh && bash /tmp/x.sh

  # 渲染到文件 / 目录（Windows 推荐，避免 PowerShell 编码问题）
  python scripts/secrets/render.py manifests/monitoring/51-grafana.yaml --out rendered/51.yaml
  python scripts/secrets/render.py "scripts/**/*.sh" --outdir rendered --flatten

  # 只检查占位符是否都能解释（不输出内容、绝不打印真值）
  python scripts/secrets/render.py --check
  python scripts/secrets/render.py --check docs/02-流水线与交付/Jenkins流水线.md

  # 原地改写（慎用；会覆盖源文件，源文件里就没有占位符了）
  python scripts/secrets/render.py scripts/xx.sh --inplace

返回码：0 成功；3 有占位符未在 .env 定义；4 用法错误。
"""

import argparse
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLACEHOLDER = re.compile(r"__([A-Z][A-Z0-9_]{2,})__|(?<!\$)\$\{([A-Z][A-Z0-9_]{2,})\}")
SHELL_EXT = (".sh", ".bash", ".py", ".groovy", ".Jenkinsfile")
CONF_EXT = (".yaml", ".yml", ".md", ".json", ".conf", ".txt")

# 通用/外部变量：不是凭据，不要求在 .env 里定义
GENERIC = {
    "TAG", "URL", "DN", "HASH", "VAR", "XXX", "FIRST", "DT", "URIS", "PKG",
    "BUILD_NUMBER", "CI_COMMIT_REF_NAME", "CI_COMMIT_REF_SLUG", "CI_PROJECT_DIR",
    "IMAGE_NAME", "ARTIFACT_REPO", "ARTIFACTORY_URL", "KUBECONFIG_FILEPATH",
    "KUBERNETES_NODE_NAME", "MAVEN_HOME", "CNI_MTU", "ARGOCD_SVC_IP",
    "DS_PROMETHEUS", "VAR_DATASOURCE", "NAMESPACE", "HOST", "PORT", "USER",
    "SSH_PASSWORD", "PASSWORD",
}


def find_env(explicit=None):
    if explicit:
        return explicit
    cands = [os.path.join(HERE, ".env"), os.path.join(HERE, "..", "..", ".env"),
             os.path.join(os.getcwd(), ".env")]
    for c in cands:
        if os.path.isfile(c):
            return os.path.normpath(c)
    return None


def load_env(path):
    env = {}
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k, v = k.strip(), v.strip()
            if v[:1] in ('"', "'") and v[-1:] == v[:1]:
                v = v[1:-1]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
                env[k] = v
    return env


def style_of(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in SHELL_EXT:
        return "shell"
    if ext in CONF_EXT:
        return "conf"
    return "both"


def render_text(text, env, style):
    missing = []

    def pick(underscore, brace):
        key = underscore or brace
        # .sh 只认 __VAR__；.yaml/.md 只认 ${VAR}；其它两种都认
        if style == "shell" and underscore is None:
            return None
        if style == "conf" and brace is None:
            return None
        return key

    def sub(m):
        key = pick(m.group(1), m.group(2))
        if key is None:
            return m.group(0)
        if key in env:
            return env[key]
        if key in GENERIC:
            return m.group(0)
        if key in os.environ:
            return os.environ[key]
        missing.append(key)
        return m.group(0)

    out = PLACEHOLDER.sub(sub, text)
    return out, sorted(set(missing))


def expand(paths):
    res = []
    for p in paths:
        hits = glob.glob(p, recursive=True) if any(c in p for c in "*?[") else [p]
        res.extend(hits or [p])
    return [h for h in res if os.path.isfile(h)]


def main():
    ap = argparse.ArgumentParser(add_help=True, description="用 .env 渲染仓库里的凭据占位符")
    ap.add_argument("paths", nargs="*", help="待渲染或待检查的文件（支持通配符）")
    ap.add_argument("--env", help="指定 .env 路径（默认自动向上查找）")
    ap.add_argument("--out", help="输出到指定文件")
    ap.add_argument("--outdir", help="输出到指定目录（保留相对路径；配合 --flatten 只留文件名）")
    ap.add_argument("--flatten", action="store_true", help="与 --outdir 连用，输出平铺到一层")
    ap.add_argument("--inplace", action="store_true", help="原地改写源文件")
    ap.add_argument("--check", action="store_true", help="只检查占位符可解析性，不输出内容")
    ap.add_argument("--quiet", action="store_true", help="check 模式下只报问题")
    args = ap.parse_args()

    env_path = find_env(args.env)
    if not env_path or not os.path.isfile(env_path):
        sys.stderr.write("[render] 找不到 .env：先 cp .env.example .env 并填值\n")
        return 4
    env = load_env(env_path)

    paths = expand(args.paths) if args.paths else expand([os.path.join(HERE, "..", "**", "*")])
    paths = [p for p in paths if os.path.abspath(p) != os.path.abspath(__file__)]

    bad = 0
    written = 0
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8-sig") as f:
                text = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        out, missing = render_text(text, env, style_of(p))
        if missing:
            bad += 1
            sys.stderr.write("[missing] %s -> %s\n" % (p, ", ".join(missing)))
            continue
        if args.check:
            if not args.quiet:
                sys.stderr.write("[ok] %s\n" % p)
            continue
        if args.inplace:
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write(out)
            written += 1
        elif args.out:
            d = os.path.dirname(args.out)
            if d:
                os.makedirs(d, exist_ok=True)
            with open(args.out, "w", encoding="utf-8", newline="") as f:
                f.write(out)
            written += 1
        elif args.outdir:
            name = os.path.basename(p) if args.flatten else os.path.relpath(p, os.getcwd())
            dst = os.path.join(args.outdir, name)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8", newline="") as f:
                f.write(out)
            written += 1
        else:
            sys.stdout.write(out)
        if args.out or args.outdir or args.inplace:
            sys.stderr.write("[written] %s\n" % p)

    if args.check and not args.quiet:
        sys.stderr.write("[render] 检查文件 %d 个，无法解析 %d 个\n" % (len(paths), bad))
    if args.out or args.outdir or args.inplace:
        sys.stderr.write("[render] 已输出 %d 个文件（其余为占位符未定义被跳过）\n" % written)
    return 3 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
