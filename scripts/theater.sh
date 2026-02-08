#!/usr/bin/env bash
# =============================================================================
# theater.sh — ENSEMBLE CAST Theater & Couch v2
#
# 左: Theater Web UI（ブラウザ）+ show-live.sh（ターミナル確認用）
# 右: Claude Code（🍿 Couch — 副音声コメンタリー・感想戦）
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

# 既存セッションチェック — 古いセッションは破棄して再作成
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${YELLOW}【報】${NC} 古いシアターセッションを破棄して再作成します..."
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 0.5
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
echo -e "${DIM}  左画面: Theater Web UI（ブラウザ）+ ターミナル LIVE${NC}"
echo -e "${DIM}  右画面: 🍿 Couch（Claude と副音声コメンタリー・感想戦）${NC}"
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

# 右ペイン背景色（ちょっと暗め）
tmux select-pane -t "$RIGHT_PANE" -P 'bg=#1a1a2e'

# --- Theater Web UI サーバー（バックグラウンド起動） ---
THEATER_PORT=3939
THEATER_PIDFILE="${PROJECT_PATH}/logs/.theater-server.pid"
python3 "${PROJECT_PATH}/scripts/theater-server.py" \
  --port "$THEATER_PORT" --base "$PROJECT_PATH" &
THEATER_PID=$!
echo "$THEATER_PID" > "$THEATER_PIDFILE"
# セッション終了時にサーバーも停止
tmux set-hook -t "$SESSION" session-closed \
  "run-shell 'kill \$(cat ${THEATER_PIDFILE} 2>/dev/null) 2>/dev/null; rm -f ${THEATER_PIDFILE}'"

# ブラウザを開く（少し待ってから）
(
  for i in $(seq 1 10); do
    curl -s "http://localhost:$THEATER_PORT/api/health" >/dev/null 2>&1 && break
    sleep 0.5
  done
  if command -v wslview >/dev/null 2>&1; then
    wslview "http://localhost:$THEATER_PORT/theater"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:$THEATER_PORT/theater" 2>/dev/null || true
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "http://localhost:$THEATER_PORT/theater" 2>/dev/null || true
  fi
) &

# --- 管理メニュー: Ctrl+b → M ---
CTL="${PROJECT_PATH}/scripts/ensemble-ctl.sh"
tmux bind-key M display-menu -T "#[align=centre] ENSEMBLE Control " \
  "Restart All   (全体再起動)" r "display-popup -E -h 80% -w 80% -d '${PROJECT_PATH}' 'bash ${CTL} restart --wait'" \
  "Restart LIVE  (LIVE再起動)" l "run-shell -b 'bash ${CTL} restart-live'" \
  "Restart WebUI (ブラウザ再起動)" w "run-shell -b 'kill \$(cat ${THEATER_PIDFILE} 2>/dev/null) 2>/dev/null; python3 ${PROJECT_PATH}/scripts/theater-server.py --port ${THEATER_PORT} --base ${PROJECT_PATH} & echo \$! > ${THEATER_PIDFILE}'" \
  "" "" "" \
  "Status        (状態確認)"   s "display-popup -E -h 70% -w 80% 'bash ${CTL} status --wait'" \
  "Checkpoint    (状態保存)"   c "display-popup -E -h 50% -w 70% 'bash ${CTL} checkpoint --wait'" \
  "" "" "" \
  "Cancel" q ""

# --- 左ペイン: Theater Web UI 案内 + show-live.sh 起動 ---
tmux send-keys -t "$LEFT_PANE" "echo -e '\\n  🎬 Theater Web UI: \\033[1;36mhttp://localhost:${THEATER_PORT}/theater\\033[0m\\n  📺 Control Room:   \\033[1;36mhttp://localhost:${THEATER_PORT}\\033[0m\\n  \\033[2m(ブラウザで自動的に Theater が開きます。以下はターミナル LIVE 表示)\\033[0m\\n'"
sleep 0.3
tmux send-keys -t "$LEFT_PANE" Enter
sleep 0.5
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

# Claude Code に初期プロンプト送信（v2: Theater + 撮影中の両方をカバー）
# 注意: tmux send-keys は改行を Enter として解釈するため、1行で送信する
tmux send-keys -t "$RIGHT_PANE" "あなたは ENSEMBLE CAST の Theater で映画を一緒に見る相棒（🍿）です。左画面にはブラウザで Theater Web UI が表示されています。できること: episodes/ の脚本YAMLを読んでエピソード内容を把握する / Ownerと感想戦を楽しむ（副音声コメンタリーのノリで技術的な裏話も交える） / Ownerが「EP.N の脚本書いて」と言ったら素材を集めて脚本を生成する / 撮影中なら logs/activity.log や cast/roster.yaml から現在の状況も把握できる。まず episodes/ と cast/roster.yaml を読んで、今の状況を把握してください。"
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
echo -e "${DIM}  ブラウザ: Theater Web UI で映画鑑賞${NC}"
echo -e "${DIM}  左画面: ターミナル LIVE 表示（確認用）${NC}"
echo -e "${DIM}  右画面: 🍿 Couch（Claude と副音声コメンタリー）${NC}"
echo ""
echo -e "${YELLOW}  管理メニュー: Ctrl+b → M${NC}"
echo -e "${DIM}    再起動・LIVE再起動・WebUI再起動・状態確認・チェックポイント保存${NC}"
echo ""
