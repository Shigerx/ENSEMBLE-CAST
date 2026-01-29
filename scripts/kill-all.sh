#!/usr/bin/env bash
# kill-all.sh — 全Agent停止（クランクアップ）
#
# Usage:
#   bash scripts/kill-all.sh          通常停止（全員Idle確認後に終了）
#   bash scripts/kill-all.sh --force  強制停止（即座に終了、フリーズ時用）

set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
DIM='\033[2m'
NC='\033[0m'

FORCE=false
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
  FORCE=true
fi

echo -e "${RED}"
cat << 'EOF'
  ╔══════════════════════════════════════════╗
  ║                                          ║
  ║   🎬 THAT'S A WRAP! — 撮影終了！ 🎬      ║
  ║                                          ║
  ╚══════════════════════════════════════════╝
EOF
echo -e "${NC}"

if ! tmux has-session -t ensemble 2>/dev/null; then
  echo -e "${YELLOW}【報】${NC} セッションが見つかりません。既に終了済みです。"
  exit 0
fi

# --force: 即座に終了
if [ "$FORCE" = true ]; then
  echo -e "${RED}【動】${NC} 強制停止モード — 即座に終了します"
  tmux kill-session -t ensemble
  echo -e "${GREEN}【成】${NC} 全キャスト強制解散。お疲れ様でした！"
  exit 0
fi

# 通常停止: 全ペインのBusy/Idleを確認
echo -e "${CYAN}【報】${NC} 各ペインの状態を確認中..."

BUSY_PANES=()
for pane_id in $(tmux list-panes -t ensemble -F '#{pane_id}'); do
  pane_title=$(tmux display-message -t "$pane_id" -p '#{pane_title}' 2>/dev/null || echo "unknown")
  last_lines=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null | tail -5)

  if echo "$last_lines" | grep -qiE "thinking|Effecting|Boondoggling|Puzzling|Calculating|Fermenting|Crunching|Esc to interrupt"; then
    BUSY_PANES+=("$pane_id ($pane_title)")
    echo -e "  ${YELLOW}⏳ $pane_title ($pane_id)${NC} — 処理中"
  else
    echo -e "  ${GREEN}✅ $pane_title ($pane_id)${NC} — Idle"
  fi
done

if [ ${#BUSY_PANES[@]} -gt 0 ]; then
  echo ""
  echo -e "${YELLOW}【報】${NC} 処理中のペインがあります:"
  for p in "${BUSY_PANES[@]}"; do
    echo -e "  ${YELLOW}⏳ $p${NC}"
  done
  echo ""
  echo -e "  ${DIM}待機して終了するか、強制終了するか選んでください:${NC}"
  echo -e "  [1] 待機する（処理完了まで30秒ごとに再チェック、最大5分）"
  echo -e "  [2] 強制終了（今すぐ終了）"
  echo -e "  [3] キャンセル"
  echo ""
  read -p "  選択 [1/2/3]: " choice

  case "$choice" in
    1)
      echo -e "${CYAN}【報】${NC} 全員がIdleになるまで待機します（最大5分）..."
      MAX_WAIT=10  # 30秒 x 10 = 5分
      for i in $(seq 1 $MAX_WAIT); do
        sleep 30
        ALL_IDLE=true
        for pane_id in $(tmux list-panes -t ensemble -F '#{pane_id}' 2>/dev/null); do
          last_lines=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null | tail -5)
          if echo "$last_lines" | grep -qiE "thinking|Effecting|Boondoggling|Puzzling|Calculating|Fermenting|Crunching|Esc to interrupt"; then
            ALL_IDLE=false
            break
          fi
        done
        if [ "$ALL_IDLE" = true ]; then
          echo -e "${GREEN}【成】${NC} 全員Idle確認！"
          break
        fi
        echo -e "${DIM}  ... まだ処理中 (${i}/${MAX_WAIT})${NC}"
      done
      if [ "$ALL_IDLE" = false ]; then
        echo -e "${YELLOW}【報】${NC} 5分経過してもBusyのペインがあります。強制終了します。"
      fi
      tmux kill-session -t ensemble
      echo -e "${GREEN}【成】${NC} 全キャスト解散。お疲れ様でした！"
      ;;
    2)
      tmux kill-session -t ensemble
      echo -e "${GREEN}【成】${NC} 全キャスト強制解散。お疲れ様でした！"
      ;;
    3)
      echo -e "${CYAN}【報】${NC} キャンセルしました。セッションは継続中です。"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}【報】${NC} 無効な入力。キャンセルします。"
      exit 1
      ;;
  esac
else
  # 全員Idle → そのまま終了
  tmux kill-session -t ensemble
  echo -e "${GREEN}【成】${NC} 全キャスト解散。お疲れ様でした！"
fi
