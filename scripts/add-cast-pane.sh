#!/usr/bin/env bash
# add-cast-pane.sh — キャスト用ペイン動的追加
# Usage: bash scripts/add-cast-pane.sh <slug> <character_name>
#
# 1. ensembleセッションに新しいペインを追加
# 2. ペインタイトルをslugに設定
# 3. tiled layoutに再配置
# 出力: 新しいペインの固有ID（%N形式）を標準出力に返す

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: bash scripts/add-cast-pane.sh <slug> <character_name>" >&2
  exit 1
fi

SLUG="$1"
CHARACTER_NAME="$2"
PROJECT_PATH="/mnt/c/Users/shige/antigravity/ENSEMBLE-CAST"

# 新しいペインを作成 → 固有ID（%N形式）を取得
NEW_PANE=$(tmux split-window -t ensemble -P -F '#{pane_id}' -c "$PROJECT_PATH")

# ペインタイトルを設定
tmux select-pane -t "$NEW_PANE" -T "${SLUG}"

# tiled layoutに再配置
tmux select-layout -t ensemble tiled

# Cast PS1カスタマイズ（ブルー）
tmux send-keys -t "$NEW_PANE" "export PS1='(\033[1;34m🎭${SLUG}\033[0m) \033[1;32m\w\033[0m\$ '"
sleep 0.3
tmux send-keys -t "$NEW_PANE" Enter

# 初期ステータスファイル作成（ライブモニター用）
echo "起動中|—|—|$(date '+%Y-%m-%dT%H:%M:%S')" > "$PROJECT_PATH/logs/${SLUG}_status.txt"

# 固有IDのみを出力（Directorがこれを読んでroster/panes更新）
echo "$NEW_PANE"
