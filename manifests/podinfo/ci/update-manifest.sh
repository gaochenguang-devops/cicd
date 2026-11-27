#!/usr/bin/env bash
# 把镜像 tag 写回 deploy 分支（不再碰 main）
# 前置：CI_COMMIT_SHA / TAG / GIT_PUSH_TOKEN 由 GitLab CI 提供
set -euo pipefail

REMOTE="http://root:${GIT_PUSH_TOKEN:?需要 GIT_PUSH_TOKEN}@192.168.200.12/root/podinfo.git"
BRANCH=deploy
TARGETS="deploy/podinfo/kustomization.yaml deploy/webapp/kustomization.yaml"

git config user.email "ci@local"
git config user.name  "GitLab CI"

echo "== 门禁 1：本流水线必须是最新 main HEAD =="
git fetch --quiet "$REMOTE" main
MAIN_SHA=$(git rev-parse FETCH_HEAD)
echo "   pipeline=$CI_COMMIT_SHA  main=$MAIN_SHA"
if [ "$MAIN_SHA" != "$CI_COMMIT_SHA" ]; then
  echo "main 已前进到 ${MAIN_SHA:0:8}，本流水线（${CI_COMMIT_SHA:0:8}）已过期，跳过写回（由最新流水线负责部署）"
  exit 0
fi

echo "== 门禁 2：以远端 deploy 为基重建一次提交（最多 3 次）=="
for i in 1 2 3; do
  git fetch --quiet "$REMOTE" "$BRANCH"
  git reset --quiet --hard FETCH_HEAD      # 同时清掉 fetch 策略遗留的脏工作区

  sed -i "s#newTag: .*#newTag: ${TAG}#" $TARGETS
  # 两份清单都必须命中，避免 sed 静默没改到
  for f in $TARGETS; do
    grep -q "newTag: ${TAG}" "$f" || { echo "$f 未写入 $TAG，中止" >&2; exit 1; }
  done
  echo "  清单目标 tag：$(grep -h 'newTag' $TARGETS | tr -d ' ' | tr '\n' ' ')"

  git add $TARGETS
  if git diff --quiet --cached; then
    echo "deploy 分支已是 $TAG，无需提交"; exit 0
  fi
  git commit --quiet -m "deploy: podinfo ${TAG}"

  if git push --quiet "$REMOTE" "HEAD:$BRANCH"; then
    echo "deploy 分支已更新 → ${TAG}（第 $i 次尝试）"; exit 0
  fi
  echo "  推送被拒（第 $i 次），2s 后按远端最新重建"
  sleep 2
done

echo "deploy 分支连续 3 次推送失败" >&2
exit 1
