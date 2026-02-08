#!/usr/bin/env bash
# =============================================================================
# theater.sh — ENSEMBLE CAST シアター + コメンタリー席
#
# 左: シアターモード（進捗ライブ + Producer指示）
# 右: Claude Code（副音声コメンタリー・雑談）
#
# Usage: bash scripts/theater.sh
# =============================================================================
set -euo pipefail

PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="theater"

# カラー
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
MAGENTA='\033[1;35m'
DIM='\033[2m'
NC='\033[0m'
WHITE='\033[1;37m'

# 既存セッションチェック
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${YELLOW}【報】${NC} シアターセッションが既にあります。アタッチします..."
  tmux attach-session -t "$SESSION"
  exit 0
fi

# ensembleセッションが動いているか確認
if ! tmux has-session -t "ensemble" 2>/dev/null; then
  echo -e "${YELLOW}⚠️  ensembleセッションが見つかりません。${NC}"
  echo -e "${DIM}  先に launch-ensemble.sh で起動してください。${NC}"
  echo ""
  echo -e "  ${CYAN}bash launch-ensemble.sh${NC}"
  exit 1
fi

echo -e "${CYAN}"
cat << 'BANNER'
  ╔════════════════════════════════════════════╗
  ║                                            ║
  ║   🍿 ENSEMBLE CAST — THEATER & COUCH 🛋️   ║
  ║                                            ║
  ╚════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "${DIM}  左画面: シアターモード（ライブ進捗 + Producer指示）${NC}"
echo -e "${DIM}  右画面: コメンタリー席（Claude と雑談・感想戦）${NC}"
echo ""

# セッション作成（左ペイン = シアター）
tmux new-session -d -s "$SESSION" -c "$PROJECT_PATH" -x 200 -y 50

LEFT_PANE=$(tmux display-message -t "${SESSION}:0.0" -p '#{pane_id}')

# 右ペイン = コメンタリー（Claude Code）
RIGHT_PANE=$(tmux split-window -t "${SESSION}:0" -h -P -F '#{pane_id}' -c "$PROJECT_PATH")

# レイアウト: 50/50 均等分割
tmux select-layout -t "${SESSION}:0" even-horizontal

# ペインタイトル
tmux select-pane -t "$LEFT_PANE" -T "🎬 THEATER"
tmux select-pane -t "$RIGHT_PANE" -T "🍿 COUCH"

# ペインボーダー表示（Windows Terminal対応: スタイル強調）
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #[bold]#{pane_title}#[nobold] "
tmux set-option -t "$SESSION" pane-border-style "fg=colour240"
tmux set-option -t "$SESSION" pane-active-border-style "fg=colour214,bold"
tmux set-option -t "$SESSION" mouse on

# --- 管理メニュー: Ctrl+b → M ---
CTL="${PROJECT_PATH}/scripts/ensemble-ctl.sh"
tmux bind-key M display-menu -T "#[align=centre] ENSEMBLE Control " \
  "Restart All   (全体再起動)" r "display-popup -E -h 80% -w 80% -d '${PROJECT_PATH}' 'bash ${CTL} restart --wait'" \
  "Restart LIVE  (LIVE再起動)" l "run-shell -b 'bash ${CTL} restart-live'" \
  "" "" "" \
  "Status        (状態確認)"   s "display-popup -E -h 70% -w 80% 'bash ${CTL} status --wait'" \
  "Checkpoint    (状態保存)"   c "display-popup -E -h 50% -w 70% 'bash ${CTL} checkpoint --wait'" \
  "" "" "" \
  "Cancel" q ""

# 右ペイン背景色（ちょっと暗め）
tmux select-pane -t "$RIGHT_PANE" -P 'bg=#1a1a2e'

# --- 左ペイン: シアターモード起動 ---
tmux send-keys -t "$LEFT_PANE" "bash scripts/show-live.sh --interactive"
sleep 0.3
tmux send-keys -t "$LEFT_PANE" Enter

# --- 右ペイン: Claude Code 起動 ---
tmux send-keys -t "$RIGHT_PANE" "export PS1='(\033[1;33m🍿Couch\033[0m) \033[1;32m\w\033[0m\$ '"
sleep 0.3
tmux send-keys -t "$RIGHT_PANE" Enter
sleep 0.5

tmux send-keys -t "$RIGHT_PANE" "claude --dangerously-skip-permissions"
sleep 0.3
tmux send-keys -t "$RIGHT_PANE" Enter

# 右ペインにフォーカス（すぐ話しかけられるように）
tmux select-pane -t "$RIGHT_PANE"

# Claude Code 初期化待ち
echo -e "${GREEN}【成】${NC} シアターセッション作成完了"
echo ""

sleep 8

# Claude Code に初期プロンプト送信
tmux send-keys -t "$RIGHT_PANE" "あなたはENSEMBLE CASTのコメンタリー席の相棒です。左画面でマルチエージェント開発が進行中です。Ownerと一緒に進捗を見ながら、感想・冗談・解説を楽しく話してください。映画の副音声コメンタリーのノリで。まず logs/activity.log と cast/roster.yaml を読んで、今何が起きているか把握してください。"
sleep 0.5
tmux send-keys -t "$RIGHT_PANE" Enter

echo -e "${GREEN}"
cat << 'EOF'
  ╔════════════════════════════════════════════╗
  ║                                            ║
  ║   🍿 ポップコーンを用意して...              ║
  ║   🛋️  ソファに座って...                     ║
  ║   🎬 上映開始！                             ║
  ║                                            ║
  ╚════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo -e "${WHITE}  次のコマンドでシアターに入ってください:${NC}"
echo -e "    ${CYAN}tmux attach-session -t theater${NC}"
echo ""
echo -e "${DIM}  左画面で進捗を見ながら、右画面でClaudeと雑談できます。${NC}"
echo -e "${DIM}  左画面の 🍿 Owner ▶ でProducerに指示も出せます。${NC}"
echo ""
echo -e "${YELLOW}  管理メニュー: Ctrl+b → M${NC}"
echo -e "${DIM}    再起動・LIVE再起動・状態確認・チェックポイント保存${NC}"
echo ""
