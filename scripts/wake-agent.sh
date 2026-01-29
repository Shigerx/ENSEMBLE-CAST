#!/usr/bin/env bash
# wake-agent.sh — 2コール send-keys ラッパー
# Usage: bash scripts/wake-agent.sh <pane_id> "送信テキスト"
#
# pane_id は tmux固有ID（%N形式）を直接受け取る。
# ensemble: プレフィックスは不要。
#
# 2コールルール:
#   1. テキストを送信
#   2. 0.5秒待機
#   3. Enterキーを送信

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: bash scripts/wake-agent.sh <pane_id> <text>" >&2
  echo "  pane_id: tmux固有ID（%N形式、例: %0, %1, %5）" >&2
  exit 1
fi

PANE_ID="$1"
TEXT="$2"

# コール1: テキスト送信（%IDを直接指定）
tmux send-keys -t "$PANE_ID" "$TEXT"

# 待機
sleep 0.5

# コール2: Enter送信
tmux send-keys -t "$PANE_ID" Enter
