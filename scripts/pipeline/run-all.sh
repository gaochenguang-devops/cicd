#!/bin/bash
# 一键回归：按顺序执行已验证的用例分组（约 15 分钟）
# 只包含断言已校准的脚本；44/56 为一次性故障注入，需按需手工执行
set -uo pipefail
T=/root/cicd-test
for s in 41-stage-a2.sh 42-stage-b.sh 43-stage-c1.sh 46-stage-d.sh 52-cred-final.sh 53-stage-e.sh 55-poll-timing.sh 57-recover.sh; do
  echo
  echo "=============================================="
  echo "== RUN $s"
  echo "=============================================="
  bash "$T/$s" 2>&1
  echo "-- exit=$?"
done
echo
echo "=============================================="
echo "== 复位现场"
bash "$T/99-restore.sh"
