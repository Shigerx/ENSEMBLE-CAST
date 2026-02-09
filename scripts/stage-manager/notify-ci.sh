#!/usr/bin/env bash
# notify-ci.sh — CI失敗時に関係者を起床させる
# ci.js 完了後に post-commit hook から呼び出される
#
# 動作:
#   1. 直近のブランチ名からCI結果ファイルを特定
#   2. overall が "fail" なら関係者を起床
#   3. "pass" なら何もしない

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# ブランチ名取得
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$BRANCH" ]; then
  exit 0  # detached HEAD
fi

# ブランチ名をスラッグ化（/ → -）
BRANCH_SLUG=$(echo "$BRANCH" | tr '/' '-')

# CI結果ファイル
RESULT_FILE="$REPO_ROOT/queue/ci_results/${BRANCH_SLUG}.yaml"

if [ ! -f "$RESULT_FILE" ]; then
  exit 0  # 結果ファイルなし（ci.jsが実行されなかった）
fi

# overall を簡易パース
OVERALL=$(grep '^overall:' "$RESULT_FILE" | sed 's/overall: *//;s/"//g' | tr -d "'" | tr -d ' ')

if [ "$OVERALL" != "fail" ]; then
  exit 0  # pass なら通知不要
fi

# --- 失敗時の通知 ---

# cast/<slug>/... 形式からslugを取得
CAST_SLUG=""
if echo "$BRANCH" | grep -q '^cast/'; then
  CAST_SLUG=$(echo "$BRANCH" | cut -d'/' -f2)
fi

# panes.yaml のパス
PANES_FILE="$REPO_ROOT/config/panes.yaml"
if [ ! -f "$PANES_FILE" ]; then
  exit 0
fi

# wake-agent.sh のパス
WAKE_SCRIPT="$REPO_ROOT/scripts/wake-agent.sh"
if [ ! -f "$WAKE_SCRIPT" ]; then
  exit 0
fi

# Cast を起床（ブランチが cast/<slug>/... 形式の場合）
if [ -n "$CAST_SLUG" ]; then
  # panes.yaml から Cast の pane_id を取得（簡易パース）
  # 形式: "  <slug>: \"%N\"" を想定
  CAST_PANE=$(grep -E "^  ${CAST_SLUG}:" "$PANES_FILE" | sed 's/.*"\(%[0-9]*\)".*/\1/' | head -1)

  if [ -n "$CAST_PANE" ]; then
    bash "$WAKE_SCRIPT" "$CAST_PANE" "[CI FAIL] ブランチ ${BRANCH} でCI失敗。queue/ci_results/${BRANCH_SLUG}.yaml を確認してください。"
  fi
fi

# Director を起床
DIRECTOR_PANE=$(grep '^director:' "$PANES_FILE" | sed 's/.*"\(%[0-9]*\)".*/\1/')
if [ -n "$DIRECTOR_PANE" ]; then
  bash "$WAKE_SCRIPT" "$DIRECTOR_PANE" "[CI FAIL] ブランチ ${BRANCH} でCI失敗。queue/ci_results/${BRANCH_SLUG}.yaml を確認してください。"
fi
