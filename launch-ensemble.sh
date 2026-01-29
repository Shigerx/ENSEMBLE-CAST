#!/usr/bin/env bash
# launch-ensemble.sh — ENSEMBLE CAST ワンクリック起動スクリプト
#
# Usage: bash launch-ensemble.sh
#
# 参考: multi-agent-shogun/shutsujin_departure.sh のパターンに準拠

set -e

PROJECT_PATH="/mnt/c/Users/shige/antigravity/ENSEMBLE-CAST"
SESSION="ensemble"

# ========================================
# ANSIカラー定数
# ========================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# ========================================
# カラーログ関数
# ========================================
log_info()    { echo -e "${CYAN}【報】${NC} $1"; }
log_success() { echo -e "${GREEN}【成】${NC} $1"; }
log_action()  { echo -e "${YELLOW}【動】${NC} $1"; }
log_error()   { echo -e "${RED}【錯】${NC} $1"; }

# ========================================
# 起動バナー（大型ASCIIアート）
# ========================================
echo -e "${RED}"
cat << 'BANNER'

   ___________________________________________________________________
  |  _______________________________________________________________ |
  | |  ___  ___ _____ _   _  ___  _  _                             | |
  | | / __|/ __|_   _| \ | || __|| \| |                            | |
  | | \__ \ |__  | | |  \| || __||    |                            | |
  | | |___/\___| |_| |_|\_||___||_|\_|                            | |
  | |_____________________________________________________________| |
  |                                                                   |
  |  SCENE: ___   TAKE: ___   ROLL: ___                              |
  |___________________________________________________________________|
      //                                                      //
     //                                                      //

BANNER
echo -e "${NC}"
echo -e "${YELLOW}   ███████╗███╗   ██╗███████╗███████╗███╗   ███╗██████╗ ██╗     ███████╗${NC}"
echo -e "${YELLOW}   ██╔════╝████╗  ██║██╔════╝██╔════╝████╗ ████║██╔══██╗██║     ██╔════╝${NC}"
echo -e "${YELLOW}   █████╗  ██╔██╗ ██║███████╗█████╗  ██╔████╔██║██████╔╝██║     █████╗  ${NC}"
echo -e "${YELLOW}   ██╔══╝  ██║╚██╗██║╚════██║██╔══╝  ██║╚██╔╝██║██╔══██╗██║     ██╔══╝  ${NC}"
echo -e "${YELLOW}   ███████╗██║ ╚████║███████║███████╗██║ ╚═╝ ██║██████╔╝███████╗███████╗${NC}"
echo -e "${YELLOW}   ╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚══════╝╚══════╝${NC}"
echo ""
echo -e "${WHITE}                 ██████╗ █████╗ ███████╗████████╗${NC}"
echo -e "${WHITE}                ██╔════╝██╔══██╗██╔════╝╚══██╔══╝${NC}"
echo -e "${WHITE}                ██║     ███████║███████╗   ██║   ${NC}"
echo -e "${WHITE}                ██║     ██╔══██║╚════██║   ██║   ${NC}"
echo -e "${WHITE}                ╚██████╗██║  ██║███████║   ██║   ${NC}"
echo -e "${WHITE}                 ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝   ${NC}"
echo ""
echo -e "${DIM}        Multi-Agent Claude Code System — tmux-based Agentic Orchestra${NC}"
echo ""

# ========================================
# STEP 0: 新規 or 継続の確認
# ========================================
HAS_PREVIOUS=false
if [ -d "$PROJECT_PATH/cast/members" ] && [ "$(ls -A "$PROJECT_PATH/cast/members" 2>/dev/null)" ]; then
  HAS_PREVIOUS=true
fi

FRESH_START=true
if [ "$HAS_PREVIOUS" = true ]; then
  echo ""
  echo -e "${YELLOW}┌──────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}│  前回のプロダクションが残っています       │${NC}"
  echo -e "${YELLOW}└──────────────────────────────────────────┘${NC}"
  echo ""
  # 前回のキャスト一覧を表示
  echo -e "${DIM}  前回のキャスト:${NC}"
  for member_dir in "$PROJECT_PATH/cast/members"/*/; do
    if [ -d "$member_dir" ]; then
      slug=$(basename "$member_dir")
      if [ -f "$member_dir/persona.yaml" ]; then
        name=$(grep -m1 'name:' "$member_dir/persona.yaml" 2>/dev/null | sed 's/.*name: *//' || echo "$slug")
        echo -e "    ${BLUE}🎭 $slug${NC} — $name"
      else
        echo -e "    ${BLUE}🎭 $slug${NC}"
      fi
    fi
  done
  if [ -f "$PROJECT_PATH/dashboard.md" ]; then
    movie=$(grep -m1 '映画:' "$PROJECT_PATH/dashboard.md" 2>/dev/null | sed 's/.*映画: *//' || true)
    project=$(grep -m1 'プロジェクト:' "$PROJECT_PATH/dashboard.md" 2>/dev/null | sed 's/.*プロジェクト: *//' || true)
    if [ -n "$movie" ] && [ "$movie" != "(未定)" ]; then
      echo -e "    ${MAGENTA}映画: $movie${NC}"
    fi
    if [ -n "$project" ] && [ "$project" != "(未定)" ]; then
      echo -e "    ${MAGENTA}プロジェクト: $project${NC}"
    fi
  fi
  echo ""
  echo -e "  ${WHITE}[1]${NC} 新規スタート（前回データをクリア）"
  echo -e "  ${WHITE}[2]${NC} 前回の続きから再開"
  echo ""
  read -p "  選択 [1/2]: " choice
  case "$choice" in
    2) FRESH_START=false ;;
    *) FRESH_START=true ;;
  esac
  echo ""
fi

# ========================================
# STEP 1: 既存セッション削除
# ========================================
log_action "[1/7] 既存セッションをクリーンアップ..."
tmux kill-session -t "$SESSION" 2>/dev/null && log_info "前回セッションを終了しました" || log_info "既存セッションなし"

# ========================================
# STEP 2: ディレクトリ初期化
# ========================================
log_action "[2/7] ディレクトリを初期化..."
mkdir -p "$PROJECT_PATH"/{cast/members,queue/tasks,queue/reports,logs,context,memory,config}

if [ "$FRESH_START" = true ]; then
  # 前回データをクリア
  rm -rf "$PROJECT_PATH/cast/members/"* 2>/dev/null || true
  rm -f "$PROJECT_PATH/context/"*.md 2>/dev/null || true
  rm -f "$PROJECT_PATH/memory/global_context.md" 2>/dev/null || true
  # logs/ をクリアして activity.log を初期化
  rm -f "$PROJECT_PATH/logs/"*.txt 2>/dev/null || true
  rm -f "$PROJECT_PATH/logs/activity.log" 2>/dev/null || true
  touch "$PROJECT_PATH/logs/activity.log"
  log_info "前回データをクリアしました"
  log_info "logs/activity.log を初期化しました"
else
  log_info "前回データを保持して再開します"
  # 継続の場合もactivity.logが存在しなければ作成
  [ -f "$PROJECT_PATH/logs/activity.log" ] || touch "$PROJECT_PATH/logs/activity.log"
fi

# ========================================
# STEP 3: Queue YAML リセット
# ========================================
log_action "[3/7] キューファイルをリセット..."

cat > "$PROJECT_PATH/queue/producer_to_director.yaml" << 'EOF'
# Producer → Director 指示キュー
orders: []
EOF

rm -f "$PROJECT_PATH/queue/tasks/"*.yaml 2>/dev/null || true
rm -f "$PROJECT_PATH/queue/reports/"*.yaml 2>/dev/null || true

# ========================================
# STEP 4: dashboard.md 初期化
# ========================================
if [ "$FRESH_START" = true ]; then
  log_action "[4/7] ダッシュボードを初期化..."
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
  cat > "$PROJECT_PATH/dashboard.md" << EOF
# 🎬 ENSEMBLE CAST — ダッシュボード

> 最終更新: ${TIMESTAMP}（Directorが更新予定）

## 🚨 要対応 — Ownerのご判断をお待ちしております
なし

## 🔄 進行中 — 撮影中
なし

## ✅ 本日の戦果
| 時刻 | キャスト | タスク | 結果 |
|------|---------|-------|------|

## 🎯 スキル化候補 — 承認待ち
なし

## プロダクション情報
- 映画: (未定)
- プロジェクト: (未定)

## キャスト
| # | キャラクター | 開発ロール | 状態 |
|---|------------|----------|------|
| - | (キャスティング待ち) | - | - |

## ⏸️ 待機中
なし

## ❓ 伺い事項
なし
EOF

  # roster.yaml 初期化
  cat > "$PROJECT_PATH/cast/roster.yaml" << 'EOF'
# ENSEMBLE CAST — キャスト一覧
# Director が生成・管理する
movie: null
members: []
EOF
else
  log_action "[4/7] ダッシュボード・roster を前回から引き継ぎ..."
fi

# ========================================
# STEP 5: tmuxセッション作成
# ========================================
log_action "[5/7] tmuxセッションを作成..."

# Producerペインでセッション作成 → 固有ID（%N）を取得
tmux new-session -d -s "$SESSION" -c "$PROJECT_PATH" -x 200 -y 50
PRODUCER_PANE=$(tmux display-message -t "${SESSION}:0.0" -p '#{pane_id}')
tmux select-pane -t "$PRODUCER_PANE" -T "producer"

# Directorペインを追加 → 固有ID（%N）を取得
DIRECTOR_PANE=$(tmux split-window -t "${SESSION}:0" -h -P -F '#{pane_id}' -c "$PROJECT_PATH")
tmux select-pane -t "$DIRECTOR_PANE" -T "director"

# レイアウト調整
tmux select-layout -t "${SESSION}:0" even-horizontal

# Producerペイン背景色（差別化）
tmux select-pane -t "$PRODUCER_PANE" -P 'bg=#1a1a2e'

# panes.yaml生成（全エージェントが参照する固有IDマッピング）
cat > "$PROJECT_PATH/config/panes.yaml" << EOF
# ENSEMBLE CAST — ペインID管理
# launch-ensemble.sh が生成。全エージェントが参照。
# tmux固有ID（%N形式）はペイン追加・削除で変わらない。
producer: "$PRODUCER_PANE"
director: "$DIRECTOR_PANE"
cast: {}
EOF

log_success "Producer pane: $PRODUCER_PANE"
log_success "Director pane: $DIRECTOR_PANE"
log_info "ペインIDを config/panes.yaml に記録"

# ========================================
# STEP 6: PS1カスタマイズ + Claude Code 起動
# ========================================
log_action "[6/7] Claude Code を起動..."

# Producer PS1（マゼンタ）
tmux send-keys -t "$PRODUCER_PANE" "export PS1='(\033[1;35m🎬Producer\033[0m) \033[1;32m\w\033[0m\$ '"
sleep 0.3
tmux send-keys -t "$PRODUCER_PANE" Enter
sleep 0.5

# Producer（Opus + Extended Thinking無効 = 即断即決・委譲専用）
tmux send-keys -t "$PRODUCER_PANE" "MAX_THINKING_TOKENS=0 claude --dangerously-skip-permissions"
sleep 0.3
tmux send-keys -t "$PRODUCER_PANE" Enter
log_success "Producer Claude Code 起動 (Opus, thinking=off)"

sleep 1

# Director PS1（レッド）
tmux send-keys -t "$DIRECTOR_PANE" "export PS1='(\033[1;31m🎬Director\033[0m) \033[1;32m\w\033[0m\$ '"
sleep 0.3
tmux send-keys -t "$DIRECTOR_PANE" Enter
sleep 0.5

# Director（デフォルトモデル + Thinking有効 = タスク分解に慎重な判断）
tmux send-keys -t "$DIRECTOR_PANE" "claude --dangerously-skip-permissions"
sleep 0.3
tmux send-keys -t "$DIRECTOR_PANE" Enter
log_success "Director Claude Code 起動 (thinking=on)"

# ========================================
# Claude Code の起動を待機（15秒）
# ========================================
log_info "Claude Code 初期化を待機中（15秒）..."
sleep 15

# ========================================
# STEP 7: 指示書送信
# ========================================
log_action "[7/7] 指示書を送信..."

# Producer に指示書を送信（2コール: テキスト → sleep → Enter）
log_info "Producer に指示書を送信..."
if [ "$FRESH_START" = true ]; then
  tmux send-keys -t "$PRODUCER_PANE" "instructions/producer.md を読んで、その指示に従ってください。CLAUDE.md も必ず読んでください。あなたはProducerです。新規スタートです。Ownerに映画とプロジェクトをヒアリングしてください。"
else
  tmux send-keys -t "$PRODUCER_PANE" "instructions/producer.md を読んで、その指示に従ってください。CLAUDE.md も必ず読んでください。あなたはProducerです。前回セッションからの再開です。dashboard.md, cast/roster.yaml, cast/members/ を確認して、Ownerに状況を報告し、次の指示を仰いでください。"
fi
sleep 0.5
tmux send-keys -t "$PRODUCER_PANE" Enter

# Director はスタンバイ（Producerが起こす）

log_success "指示書送信完了"

# ========================================
# セッション設定: マウスモード有効化 + ペインタイトル表示 + Producerペインにフォーカス
# ========================================
tmux set-option -t "$SESSION" mouse on
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
tmux select-pane -t "$PRODUCER_PANE"

# ========================================
# 隊列図（スタジオ配置図）
# ========================================
echo ""
echo -e "${CYAN}    🎬 ENSEMBLE CAST — スタジオ配置図${NC}"
echo ""
echo -e "${MAGENTA}    ┌─────────────┐${NC}     ${RED}┌─────────────┐${NC}"
echo -e "${MAGENTA}    │  🎬         │${NC}     ${RED}│  🎬         │${NC}"
echo -e "${MAGENTA}    │  PRODUCER   │${NC} ──▶ ${RED}│  DIRECTOR   │${NC}"
echo -e "${MAGENTA}    │  ($PRODUCER_PANE)       │${NC}     ${RED}│  ($DIRECTOR_PANE)       │${NC}"
echo -e "${MAGENTA}    │  統括       │${NC}     ${RED}│  演出       │${NC}"
echo -e "${MAGENTA}    └─────────────┘${NC}     ${RED}└──────┬──────┘${NC}"
echo -e "                               ${RED}│${NC}"
echo -e "              ┌────────────────${RED}┼${NC}────────────────┐"
echo -e "              ▼                ${RED}▼${NC}                ▼"
echo -e "${BLUE}       ┌───────────┐   ┌───────────┐   ┌───────────┐${NC}"
echo -e "${BLUE}       │ 🎭 CAST1  │   │ 🎭 CAST2  │   │ 🎭 CAST..│${NC}"
echo -e "${BLUE}       │ (待機中)   │   │ (待機中)   │   │ (待機中)  │${NC}"
echo -e "${BLUE}       └───────────┘   └───────────┘   └───────────┘${NC}"
echo ""

# ========================================
# 完了バナー
# ========================================
echo -e "${GREEN}"
cat << 'EOF'
  ╔═══════════════════════════════════════════════╗
  ║                                               ║
  ║     🎬 QUIET ON SET... ACTION! 🎬             ║
  ║                                               ║
  ║     スタジオ起動完了！撮影開始！                ║
  ║                                               ║
  ╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${WHITE}  次のコマンドでセッションに入ってください:${NC}"
echo -e "    ${CYAN}tmux attach-session -t ensemble${NC}"
echo ""
echo -e "${DIM}  ペイン構成:${NC}"
echo -e "    ${MAGENTA}[左] Producer ($PRODUCER_PANE)${NC} — Ownerとの対話窓口"
echo -e "    ${RED}[右] Director ($DIRECTOR_PANE)${NC} — 起床待ち（Producerが起こします）"
echo ""
echo -e "${DIM}  ペインIDは config/panes.yaml に記録済み。${NC}"
echo -e "${DIM}  Producerが映画とプロジェクトについてヒアリングします。${NC}"
echo -e "${DIM}  お好きな映画と作りたいプロジェクトを伝えてください!${NC}"
echo ""
