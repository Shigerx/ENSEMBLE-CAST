#!/usr/bin/env bash
# =============================================================================
# ENSEMBLE CAST — ワンクリック起動スクリプト
# scale: small → v2モード（Producer + Director + Cast）
# scale: large → v3モード（Producer + LP + Director×N + Cast×N）
# =============================================================================
set -euo pipefail

PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="ensemble"

# Config files
PRODUCTION_YAML="$PROJECT_PATH/config/production.yaml"
UNITS_YAML="$PROJECT_PATH/config/units.yaml"
ROSTER_YAML="$PROJECT_PATH/cast/roster.yaml"
PANES_YAML="$PROJECT_PATH/config/panes.yaml"

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
log_error()   { echo -e "${RED}【錯】${NC} $1" >&2; exit 1; }

# ========================================
# 簡易 YAML 値取得（grep + sed、外部依存なし）
# ========================================
yaml_get_value() {
  local file="$1" key="$2"
  grep -E "^${key}:" "$file" 2>/dev/null | sed -E 's/^[^:]+:\s*//' | sed -E "s/^[\"']|[\"']$//g" | tr -d '\r' || true
}

# roster.yaml から slug 一覧を取得
roster_get_slugs() {
  local file="$1"
  grep -E '^\s+-\s+slug:' "$file" 2>/dev/null | sed -E 's/.*slug:\s*"?([^"]+)"?.*/\1/' | tr -d '\r' || true
}

# roster.yaml から reviewer の slug を取得
roster_get_reviewer_slugs() {
  local file="$1"
  local current_slug=""
  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"
    if echo "$line" | grep -qE '^\s+-\s+slug:'; then
      current_slug="$(echo "$line" | sed -E 's/.*slug:\s*"?([^"]+)"?.*/\1/')"
    fi
    if [ -n "$current_slug" ] && echo "$line" | grep -qE '^\s+is_reviewer:\s*true'; then
      echo "$current_slug"
      current_slug=""
    fi
  done < "$file"
}

# ========================================
# scale 判定
# ========================================
get_scale() {
  if [ ! -f "$PRODUCTION_YAML" ]; then
    echo "small"
    return
  fi
  local scale
  scale=$(yaml_get_value "$PRODUCTION_YAML" "scale")
  if [ "$scale" = "large" ]; then
    echo "large"
  else
    echo "small"
  fi
}

# ========================================
# ペイン作成ヘルパー（scale: large 用）
# ========================================
create_pane() {
  local label="$1"
  local color="${2:-32}"

  local pane_id
  pane_id=$(tmux split-window -t "$SESSION" -P -F '#{pane_id}' -c "$PROJECT_PATH")
  tmux select-pane -t "$pane_id" -T "$label"
  tmux select-layout -t "$SESSION" tiled

  tmux send-keys -t "$pane_id" "export PS1='(\033[1;${color}m${label}\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.3
  tmux send-keys -t "$pane_id" Enter

  echo "$pane_id"
}

# ========================================
# 2コール send-keys ヘルパー
# ========================================
safe_send_keys() {
  local pane_id="$1"
  local text="$2"
  tmux send-keys -t "$pane_id" "$text"
  sleep 0.5
  tmux send-keys -t "$pane_id" Enter
}

# ========================================
# 起動バナー
# ========================================
show_banner() {
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
}

# ========================================
# 新規/継続 判定
# ========================================
FRESH_START=true

check_previous_session() {
  local has_previous=false
  if [ -d "$PROJECT_PATH/cast/members" ] && [ "$(ls -A "$PROJECT_PATH/cast/members" 2>/dev/null)" ]; then
    has_previous=true
  fi

  if [ "$has_previous" = true ]; then
    echo ""
    echo -e "${YELLOW}┌──────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  前回のプロダクションが残っています       │${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${DIM}  前回のキャスト:${NC}"
    for member_dir in "$PROJECT_PATH/cast/members"/*/; do
      if [ -d "$member_dir" ]; then
        local slug
        slug=$(basename "$member_dir")
        if [ -f "$member_dir/persona.yaml" ]; then
          local name
          name=$(grep -m1 'name:' "$member_dir/persona.yaml" 2>/dev/null | sed 's/.*name: *//' || echo "$slug")
          echo -e "    ${BLUE}🎭 $slug${NC} — $name"
        else
          echo -e "    ${BLUE}🎭 $slug${NC}"
        fi
      fi
    done
    if [ -f "$PROJECT_PATH/dashboard.md" ]; then
      local movie project
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
}

# ========================================
# STEP 1: 既存セッション削除
# ========================================
cleanup_session() {
  log_action "[1/7] 既存セッションをクリーンアップ..."

  # Stage Manager のプロセスを停止
  local pid_file="$PROJECT_PATH/logs/stage_manager_pids.txt"
  if [ -f "$pid_file" ]; then
    while IFS= read -r pid; do
      [ -z "$pid" ] && continue
      kill "$pid" 2>/dev/null || true
    done < "$pid_file"
    : > "$pid_file"
  fi

  tmux kill-session -t "$SESSION" 2>/dev/null && log_info "前回セッションを終了しました" || log_info "既存セッションなし"
}

# ========================================
# STEP 2: ディレクトリ初期化
# ========================================
init_directories() {
  log_action "[2/7] ディレクトリを初期化..."
  mkdir -p "$PROJECT_PATH"/{cast/members,queue/tasks,queue/reports,queue/inter_unit,queue/lp_to_units,logs,context,memory,config,contracts/requests,contracts/types,dailies,scripts/stage-manager,.githooks}

  # Git hooks 設定
  git -C "$PROJECT_PATH" config core.hooksPath .githooks 2>/dev/null || true

  if [ "$FRESH_START" = true ]; then
    rm -rf "$PROJECT_PATH/cast/members/"* 2>/dev/null || true
    rm -f "$PROJECT_PATH/context/"*.md 2>/dev/null || true
    rm -f "$PROJECT_PATH/memory/global_context.md" 2>/dev/null || true
    rm -f "$PROJECT_PATH/logs/"*.txt 2>/dev/null || true
    rm -f "$PROJECT_PATH/logs/activity.log" 2>/dev/null || true
    touch "$PROJECT_PATH/logs/activity.log"
    log_info "前回データをクリアしました"
  else
    log_info "前回データを保持して再開します"
    [ -f "$PROJECT_PATH/logs/activity.log" ] || touch "$PROJECT_PATH/logs/activity.log"
  fi
}

# ========================================
# STEP 3: Queue YAML リセット
# ========================================
reset_queues() {
  log_action "[3/7] キューファイルをリセット..."

  cat > "$PROJECT_PATH/queue/producer_to_director.yaml" << 'EOF'
# Producer → Director 指示キュー
orders: []
EOF

  cat > "$PROJECT_PATH/queue/producer_to_lp.yaml" << 'EOF'
# EP → Line Producer 指示キュー
messages: []
EOF

  rm -f "$PROJECT_PATH/queue/tasks/"*.yaml 2>/dev/null || true
  rm -f "$PROJECT_PATH/queue/reports/"*.yaml 2>/dev/null || true
  rm -f "$PROJECT_PATH/queue/inter_unit/"*.yaml 2>/dev/null || true
  rm -f "$PROJECT_PATH/queue/lp_to_units/"*.yaml 2>/dev/null || true
}

# ========================================
# STEP 4: dashboard.md 初期化
# ========================================
init_dashboard() {
  if [ "$FRESH_START" = true ]; then
    log_action "[4/7] ダッシュボードを初期化..."
    local TIMESTAMP
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

    cat > "$PROJECT_PATH/cast/roster.yaml" << 'EOF'
# ENSEMBLE CAST — キャスト一覧
# Director が生成・管理する
movie: null
members: []
EOF
  else
    log_action "[4/7] ダッシュボード・roster を前回から引き継ぎ..."
  fi
}

# ========================================
# STEP 5: tmuxセッション作成 + Claude Code 起動
# ========================================
create_session_small() {
  log_action "[5/7] tmuxセッション作成 + Claude Code 起動（scale: small）..."

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

  # panes.yaml 生成
  {
    echo "# ENSEMBLE CAST — ペインID管理"
    echo "# launch-ensemble.sh が生成。全エージェントが参照。"
    echo "# tmux固有ID（%N形式）はペイン追加・削除で変わらない。"
    echo "producer: \"$PRODUCER_PANE\""
    echo "director: \"$DIRECTOR_PANE\""
    echo "cast:"
  } > "$PANES_YAML"

  log_success "Producer pane: $PRODUCER_PANE"
  log_success "Director pane: $DIRECTOR_PANE"

  # --- Producer Claude Code 起動 ---
  safe_send_keys "$PRODUCER_PANE" "export PS1='(\033[1;35m🎬Producer\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.5
  safe_send_keys "$PRODUCER_PANE" "MAX_THINKING_TOKENS=0 claude --dangerously-skip-permissions"
  log_success "Producer Claude Code 起動 (Opus, thinking=off)"

  sleep 1

  # --- Director Claude Code 起動 ---
  safe_send_keys "$DIRECTOR_PANE" "export PS1='(\033[1;31m🎬Director\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.5
  safe_send_keys "$DIRECTOR_PANE" "claude --dangerously-skip-permissions"
  log_success "Director Claude Code 起動 (thinking=on)"

  # 継続モード: roster.yaml から Cast ペインを作成して Claude Code 起動
  if [ "$FRESH_START" = false ] && [ -f "$ROSTER_YAML" ]; then
    local slugs
    slugs=$(roster_get_slugs "$ROSTER_YAML")
    if [ -n "$slugs" ]; then
      local reviewer_slugs
      reviewer_slugs=$(roster_get_reviewer_slugs "$ROSTER_YAML")

      sleep 1
      while IFS= read -r slug; do
        [ -z "$slug" ] && continue

        local color="34"  # Cast: 青
        if echo "$reviewer_slugs" | grep -qx "$slug"; then
          color="36"  # Reviewer: シアン
        fi

        # ペイン作成
        local cast_pane
        cast_pane=$(create_pane "$slug" "$color")
        echo "  $slug: \"$cast_pane\"" >> "$PANES_YAML"

        # ステータスファイル初期化
        echo "起動中|—|—|$(date '+%Y-%m-%dT%H:%M:%S')" > "$PROJECT_PATH/logs/${slug}_status.txt"

        # Claude Code 起動
        sleep 0.5
        safe_send_keys "$cast_pane" "claude --dangerously-skip-permissions"
        log_success "Cast $slug ($cast_pane) 起動"
      done <<< "$slugs"
    fi
  fi

  log_info "ペインIDを config/panes.yaml に記録"
}

create_session_large() {
  log_action "[5/7] tmuxセッション作成 + Claude Code 起動（scale: large）..."

  if [ ! -f "$UNITS_YAML" ]; then
    log_error "config/units.yaml が見つかりません。scale: large には units.yaml が必要です。"
  fi

  # Producerペインでセッション作成
  tmux new-session -d -s "$SESSION" -c "$PROJECT_PATH" -x 200 -y 50
  PRODUCER_PANE=$(tmux display-message -t "${SESSION}:0.0" -p '#{pane_id}')
  tmux select-pane -t "$PRODUCER_PANE" -T "producer"
  tmux select-pane -t "$PRODUCER_PANE" -P 'bg=#1a1a2e'

  # Line Producer ペイン作成
  LP_PANE=$(create_pane "line_producer" "35")

  # panes.yaml ヘッダー
  {
    echo "# ENSEMBLE CAST — ペインID管理"
    echo "# launch-ensemble.sh が生成。全エージェントが参照。"
    echo "# tmux固有ID（%N形式）はペイン追加・削除で変わらない。"
    echo "producer: \"$PRODUCER_PANE\""
    echo "line_producer: \"$LP_PANE\""
    echo "units:"
  } > "$PANES_YAML"

  log_success "Producer pane: $PRODUCER_PANE"
  log_success "Line Producer pane: $LP_PANE"

  # units.yaml からユニット定義を読み取って各ユニットのペイン作成
  local current_unit="" in_units=false in_cast=false

  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"
    echo "$line" | grep -qE '^\s*#|^\s*$' && continue

    if echo "$line" | grep -qE '^units:\s*$'; then
      in_units=true; continue
    fi
    if echo "$line" | grep -qE '^\S' && ! echo "$line" | grep -qE '^units:'; then
      in_units=false; in_cast=false; continue
    fi
    [ "$in_units" = false ] && continue

    local unit_name
    unit_name=$(echo "$line" | sed -nE 's/^  ([a-zA-Z_][a-zA-Z0-9_-]*):\s*$/\1/p')
    if [ -n "$unit_name" ]; then
      current_unit="$unit_name"
      in_cast=false
      local dir_pane
      dir_pane=$(create_pane "dir-${current_unit}" "33")
      echo "  $current_unit:" >> "$PANES_YAML"
      echo "    director: \"$dir_pane\"" >> "$PANES_YAML"
      echo "    cast:" >> "$PANES_YAML"
      log_info "ユニット '$current_unit' Director: $dir_pane"
      continue
    fi

    if echo "$line" | grep -qE '^\s{4}cast:\s*$'; then
      in_cast=true; continue
    fi

    if [ "$in_cast" = true ]; then
      local cast_slug
      cast_slug=$(echo "$line" | sed -nE 's/.*slug:\s*([a-zA-Z_][a-zA-Z0-9_-]*).*/\1/p')
      if [ -n "$cast_slug" ]; then
        local cast_pane
        cast_pane=$(create_pane "$cast_slug" "34")
        echo "      $cast_slug: \"$cast_pane\"" >> "$PANES_YAML"
        echo "起動中|—|—|$(date '+%Y-%m-%dT%H:%M:%S')" > "$PROJECT_PATH/logs/${cast_slug}_status.txt"
        log_info "ユニット '$current_unit' Cast: $cast_slug ($cast_pane)"
        continue
      fi
      if echo "$line" | grep -qE '^\s{4}[a-zA-Z]'; then
        in_cast=false
      fi
    fi
  done < "$UNITS_YAML"

  # --- Claude Code 起動 ---
  safe_send_keys "$PRODUCER_PANE" "export PS1='(\033[1;35m🎬Producer\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.5
  safe_send_keys "$PRODUCER_PANE" "MAX_THINKING_TOKENS=0 claude --dangerously-skip-permissions"
  log_success "Producer Claude Code 起動 (Opus, thinking=off)"

  sleep 1

  safe_send_keys "$LP_PANE" "claude --dangerously-skip-permissions"
  log_success "Line Producer Claude Code 起動 (thinking=on)"

  log_info "ペインIDを config/panes.yaml に記録"
}

# ========================================
# STEP 6: Stage Manager 起動
# ========================================
start_stage_manager() {
  log_action "[6/7] Stage Manager を起動..."

  local sm_dir="$PROJECT_PATH/scripts/stage-manager"
  local pid_file="$PROJECT_PATH/logs/stage_manager_pids.txt"
  : > "$pid_file"

  if ! command -v node &>/dev/null; then
    log_info "Node.js が見つかりません。Stage Manager はスキップします。"
    return
  fi

  if [ -f "$sm_dir/router.js" ]; then
    log_info "Stage Manager: router.js を起動"
    node "$sm_dir/router.js" &
    echo $! >> "$pid_file"
  fi

  if [ -f "$sm_dir/checkpoint.js" ]; then
    log_info "Stage Manager: checkpoint.js を起動"
    node "$sm_dir/checkpoint.js" &
    echo $! >> "$pid_file"
  fi

  if [ -f "$sm_dir/health.js" ]; then
    log_info "Stage Manager: health.js を起動"
    node "$sm_dir/health.js" &
    echo $! >> "$pid_file"
  fi

  if [ -s "$pid_file" ]; then
    log_info "Stage Manager PIDs: $(tr '\n' ' ' < "$pid_file")"
  fi
}

# ========================================
# STEP 7: 指示書送信
# ========================================
send_initial_instructions() {
  local scale="$1"

  log_action "[7/7] Claude Code 初期化を待機中（20秒）..."
  sleep 20

  log_action "指示書を送信..."

  if [ "$FRESH_START" = true ]; then
    safe_send_keys "$PRODUCER_PANE" "instructions/producer.md を読んで、その指示に従ってください。CLAUDE.md も必ず読んでください。あなたはProducerです。新規スタートです。Ownerに映画とプロジェクトをヒアリングしてください。"
  else
    safe_send_keys "$PRODUCER_PANE" "instructions/producer.md を読んで、その指示に従ってください。CLAUDE.md も必ず読んでください。あなたはProducerです。前回セッションからの再開です。dashboard.md, cast/roster.yaml, cast/members/ を確認して、Ownerに状況を報告し、次の指示を仰いでください。"
  fi
  log_success "Producer に指示書送信完了"

  # Director はスタンバイ（Producerが起こす）
  # 継続モードの場合、Director と Cast にも指示を送る
  if [ "$FRESH_START" = false ]; then
    sleep 2
    safe_send_keys "$DIRECTOR_PANE" "CLAUDE.md と instructions/director.md を読んでください。あなたはDirectorです。前回セッションからの再開です。dashboard.md, cast/roster.yaml, config/panes.yaml を確認して、Producerからの指示を待ってください。指示がなければここで停止してください。"
    log_success "Director に再開指示を送信"

    # Cast にも再開指示を送信
    if [ -f "$ROSTER_YAML" ]; then
      local slugs
      slugs=$(roster_get_slugs "$ROSTER_YAML")
      if [ -n "$slugs" ]; then
        sleep 2
        while IFS= read -r slug; do
          [ -z "$slug" ] && continue
          # panes.yaml から Cast の pane ID を取得
          local cast_pane_id
          cast_pane_id=$(grep -E "^\s+${slug}:" "$PANES_YAML" 2>/dev/null | sed -E 's/.*"(%[0-9]+)".*/\1/' || true)
          [ -z "$cast_pane_id" ] && continue

          sleep 1
          safe_send_keys "$cast_pane_id" "CLAUDE.md と instructions/cast_template.md を読んでください。あなたは ${slug} です。cast/members/${slug}/persona.yaml を読んでキャラクターを把握してください。前回セッションからの再開です。cast/members/${slug}/chronicle.yaml と queue/tasks/${slug}.yaml を確認して、Directorからの指示を待ってください。指示がなければここで停止してください。"
          log_success "Cast ${slug} (${cast_pane_id}) に再開指示を送信"
        done <<< "$slugs"
      fi
    fi
  fi
}

# ========================================
# 完了表示
# ========================================
show_complete() {
  local scale="$1"

  # セッション設定
  tmux set-option -t "$SESSION" mouse on
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
  tmux select-pane -t "$PRODUCER_PANE"

  # スタジオ配置図
  echo ""
  echo -e "${CYAN}    🎬 ENSEMBLE CAST — スタジオ配置図 (scale: $scale)${NC}"
  echo ""

  if [ "$scale" = "small" ]; then
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
  elif [ "$scale" = "large" ]; then
    echo -e "${MAGENTA}    ┌─────────────┐${NC}"
    echo -e "${MAGENTA}    │  🎬 EP      │${NC}"
    echo -e "${MAGENTA}    │  PRODUCER   │${NC}"
    echo -e "${MAGENTA}    │  ($PRODUCER_PANE)       │${NC}"
    echo -e "${MAGENTA}    └──────┬──────┘${NC}"
    echo -e "           ${MAGENTA}│${NC}"
    echo -e "           ${MAGENTA}▼${NC}"
    echo -e "${MAGENTA}    ┌─────────────┐${NC}"
    echo -e "${MAGENTA}    │  📋 LP      │${NC}"
    echo -e "${MAGENTA}    │  LINE PROD  │${NC}"
    echo -e "${MAGENTA}    │  ($LP_PANE)       │${NC}"
    echo -e "${MAGENTA}    └──────┬──────┘${NC}"
    echo -e "           ${MAGENTA}│${NC}"
    echo -e "    ┌──────┴──────┐"
    echo -e "    ▼             ▼"
    echo -e "${RED} ┌──────────┐ ┌──────────┐${NC}"
    echo -e "${RED} │ UNIT-A   │ │ UNIT-B   │${NC}"
    echo -e "${RED} │ Dir+Cast │ │ Dir+Cast │${NC}"
    echo -e "${RED} └──────────┘ └──────────┘${NC}"
  fi
  echo ""

  # 完了バナー
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
  echo -e "${DIM}  ペインIDは config/panes.yaml に記録済み。${NC}"
  echo -e "${DIM}  Producerが映画とプロジェクトについてヒアリングします。${NC}"
  echo -e "${DIM}  お好きな映画と作りたいプロジェクトを伝えてください!${NC}"
  echo ""
}

# ========================================
# メイン
# ========================================
main() {
  show_banner
  check_previous_session

  # scale 判定
  local scale
  scale=$(get_scale)
  log_info "scale: $scale"

  cleanup_session
  init_directories
  reset_queues
  init_dashboard

  case "$scale" in
    small) create_session_small ;;
    large) create_session_large ;;
    *) log_error "不明な scale: $scale（small または large を指定してください）" ;;
  esac

  start_stage_manager
  send_initial_instructions "$scale"
  show_complete "$scale"
}

main "$@"
