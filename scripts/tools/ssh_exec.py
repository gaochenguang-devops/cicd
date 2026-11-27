#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
轻量 SSH 执行器（paramiko），用于在远端服务器上执行命令，免去每次输入密码。

用法:
  python ssh_exec.py --ping                       # 连通性检查
  python ssh_exec.py "uptime && df -h"            # 执行单条命令
  python ssh_exec.py --script scripts/xx.sh       # 整段脚本一次性执行（支持循环/if）
  python ssh_exec.py --file scripts/xx.sh         # 逐行执行，遇错继续并汇总

凭据来源（优先级从高到低）:
  1. 环境变量 SSH_HOST / SSH_PORT / SSH_USER / SSH_PASSWORD（或 SSH_ROOT_PASS）/ SSH_TIMEOUT
  2. 仓库根的 .env 文件（自动向上查找 3 层目录）
  都没有就报错退出，不在代码里保留任何默认口令。

脚本里的 __VAR__ 占位符会在上传前自动用 .env 渲染，
所以 Windows/Linux 都可以直接执行 scripts/ 下的脚本文件。
"""

import os
import re
import sys
import time
import socket
import base64
import argparse
import paramiko

PLACEHOLDER = re.compile(r"__([A-Z][A-Z0-9_]{2,})__")


def find_env_file():
    """从本文件所在目录向上找 .env（最多 4 层），也检查当前工作目录。"""
    here = os.path.dirname(os.path.abspath(__file__))
    cands = []
    d = here
    for _ in range(4):
        cands.append(os.path.join(d, ".env"))
        d = os.path.dirname(d)
    cands.append(os.path.join(os.getcwd(), ".env"))
    for c in cands:
        if os.path.isfile(c):
            return c
    return None


def load_dotenv():
    path = find_env_file()
    if not path:
        return {}
    data = {}
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
                data[k] = v
    return data


DOTENV = load_dotenv()


def cfg(name, default=None):
    if name in os.environ and os.environ[name] != "":
        return os.environ[name]
    if name in DOTENV:
        return DOTENV[name]
    return default


HOST = cfg("SSH_HOST", "192.168.200.12")
PORT = int(cfg("SSH_PORT", "22"))
USER = cfg("SSH_USER", "root")
PASSWORD = cfg("SSH_PASSWORD") or cfg("SSH_ROOT_PASS")
TIMEOUT = int(cfg("SSH_TIMEOUT", "30"))


def render_placeholders(text):
    """把 __VAR__ 换成 .env 里的值；遇到未定义变量直接报错，避免把占位符发到远端。"""
    missing = []

    def sub(m):
        key = m.group(1)
        if key in DOTENV:
            return DOTENV[key]
        if key in os.environ:
            return os.environ[key]
        missing.append(key)
        return m.group(0)

    out = PLACEHOLDER.sub(sub, text)
    if missing:
        sys.stderr.write("[ssh_exec] 以下占位符在 .env 中没有定义: %s\n" % ", ".join(sorted(set(missing))))
        sys.stderr.write("[ssh_exec] 先补齐 .env（参考 .env.example），或删除该行占位符\n")
        raise SystemExit(3)
    return out


def connect():
    if not PASSWORD:
        sys.stderr.write("[ssh_exec] 缺少 SSH 口令：请在 .env 里设置 SSH_ROOT_PASS（或 SSH_PASSWORD）\n")
        raise SystemExit(2)
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=HOST, port=PORT, username=USER, password=PASSWORD,
        timeout=TIMEOUT, banner_timeout=TIMEOUT, auth_timeout=TIMEOUT,
        look_for_keys=False, allow_agent=False,
    )
    client.get_transport().set_keepalive(30)
    return client


def run(client, command, timeout=None, quiet=False, display=None):
    """执行命令并返回 (exit_code, stdout, stderr)。"""
    if display and not quiet:
        print("\n=== $ %s" % display, flush=True)
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    try:
        out_txt = stdout.read().decode("utf-8", errors="replace")
        err_txt = stderr.read().decode("utf-8", errors="replace")
    except socket.timeout:
        out_txt, err_txt = "", "[ssh_exec] read timeout"
    finally:
        code = stdout.channel.recv_exit_status()
        stdout.channel.close()

    if err_txt and err_txt.strip() == out_txt.strip():
        err_txt = ""   # 某些 paramiko 版本会把同一份输出同时落 stdout/stderr

    if not quiet:
        if out_txt:
            sys.stdout.write(out_txt); sys.stdout.flush()
        if err_txt:
            sys.stderr.write(err_txt); sys.stderr.flush()
    return code, out_txt, err_txt


def run_script(client, script_text, timeout=None, quiet=False, label="script"):
    """整段脚本 base64 传到远端 bash 执行，支持多行/循环/条件判断。"""
    b64 = base64.b64encode(script_text.encode("utf-8")).decode("ascii")
    tag = "%d" % os.getpid()
    cmd = ("echo %s | base64 -d > /tmp/.exec_%s.sh && bash /tmp/.exec_%s.sh; rc=$?; "
           "rm -f /tmp/.exec_%s.sh; exit $rc") % (b64, tag, tag, tag)
    return run(client, cmd, timeout=timeout, quiet=quiet, display=label)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", nargs="?", help="远端命令")
    ap.add_argument("--file", help="逐行执行本地脚本文件中的命令")
    ap.add_argument("--script", help="整段执行本地脚本文件（推荐）")
    ap.add_argument("--ping", action="store_true", help="连通性检查")
    ap.add_argument("--put", action="append", metavar="LOCAL=>REMOTE",
                    help="上传本地文件到远端，可重复；例: --put \"a.sh=>/root/a.sh\"")
    ap.add_argument("--timeout", type=int, default=None, help="命令超时(秒)")
    args = ap.parse_args()

    t0 = time.time()
    client = connect()
    print("[ssh] connected %s@%s:%s (%.2fs)" % (USER, HOST, PORT, time.time() - t0), flush=True)

    if args.put:
        sftp = client.open_sftp()
        for spec in args.put:
            local, remote = spec.split("=>", 1)
            rdir = os.path.dirname(remote) or "/root"
            run(client, "mkdir -p %s" % rdir, quiet=True)
            sftp.put(local, remote)
            try:
                sftp.chmod(remote, 0o755)
            except IOError:
                pass
            print("[put] %s -> %s" % (local, remote), flush=True)
        sftp.close()
        if not (args.script or args.command or args.file or args.ping):
            return 0

    try:
        if args.ping:
            code, out, _ = run(client, "uname -a; whoami; pwd", quiet=True)
            print(out.strip())
            return code

        if args.script:
            with open(args.script, "r", encoding="utf-8-sig") as f:
                return run_script(client, render_placeholders(f.read()), timeout=args.timeout, label=args.script)[0]

        if args.file:
            with open(args.file, "r", encoding="utf-8-sig") as f:
                lines = [l.rstrip("\n") for l in f]
            failures = []
            for line in lines:
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                code, _, _ = run(client, render_placeholders(s), timeout=args.timeout, display=s)
                if code != 0:
                    failures.append((s, code))
            print("\n===== summary =====")
            if failures:
                for c, k in failures:
                    print("FAIL(%s): %s" % (k, c))
                return 1
            print("ALL OK")
            return 0

        if args.command:
            return run(client, render_placeholders(args.command), timeout=args.timeout, display=args.command)[0]

        ap.print_help()
        return 2
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
