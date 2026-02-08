#!/usr/bin/env bash
# show-live.sh — ENSEMBLE CAST シアターモード
#
# Usage:
#   bash scripts/show-live.sh           # 1回表示
#   bash scripts/show-live.sh --watch   # 2秒ごと自動更新（鑑賞モード）

set -euo pipefail

PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
BOLD='\033[1m'
BG_DARK='\033[48;5;234m'
BG_DARKER='\033[48;5;232m'

# キャラクターカラーマッピング（slug → カラー）
# 固定マッピングでなく、ローテーションで割り当て
CAST_COLORS=("${RED}" "${GREEN}" "${YELLOW}" "${BLUE}" "${MAGENTA}" "${CYAN}")

# ========================================
# キャラクター情報キャッシュ
# ========================================
declare -A CHAR_NAMES
declare -A CHAR_COLORS
declare -A CHAR_EMOJIS
COLOR_INDEX=0

get_char_info() {
  # slugをサニタイズ（CR、スペース、タブ、不可視文字を除去）
  local slug
  slug=$(echo "$1" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_-]//g')

  # 空なら何もしない
  [ -z "$slug" ] && return

  # キャッシュ済みなら返す
  if [ -n "${CHAR_NAMES[$slug]+x}" ]; then
    return
  fi

  # persona.yaml から名前を取得
  local persona_file="$PROJECT_PATH/cast/members/$slug/persona.yaml"
  local name="$slug"
  local emoji="🎭"

  if [ -f "$persona_file" ]; then
    # character_name を優先、なければ name フィールド
    local cn
    cn=$(grep -m1 '^character_name:' "$persona_file" 2>/dev/null | sed 's/^character_name: *//' | tr -d '"' || true)
    if [ -n "$cn" ]; then
      name="$cn"
    else
      cn=$(grep -m1 '^name:' "$persona_file" 2>/dev/null | sed 's/^name: *//' | tr -d '"' || true)
      [ -n "$cn" ] && name="$cn"
    fi
    # emoji フィールドがあれば取得
    local e
    e=$(grep -m1 '^emoji:' "$persona_file" 2>/dev/null | sed 's/^emoji: *//' | tr -d '"' || true)
    if [ -n "$e" ]; then
      emoji="$e"
    fi
  fi

  CHAR_NAMES[$slug]="$name"
  CHAR_EMOJIS[$slug]="$emoji"
  CHAR_COLORS[$slug]="${CAST_COLORS[$((COLOR_INDEX % ${#CAST_COLORS[@]}))]}"
  COLOR_INDEX=$((COLOR_INDEX + 1))
}

# ========================================
# プログレスバー生成
# ========================================
progress_bar() {
  local percent="$1"
  local width="${2:-20}"
  local filled=$(( percent * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""

  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo "$bar"
}

# ========================================
# ターミナル幅取得
# ========================================
get_term_width() {
  local w
  w=$(tput cols 2>/dev/null || echo 80)
  echo "$w"
}

# 水平ライン
hline() {
  local w
  w=$(get_term_width)
  printf '%*s\n' "$w" '' | tr ' ' '─'
}

# ========================================
# ヘッダー
# ========================================
show_header() {
  local TIMESTAMP
  TIMESTAMP=$(date "+%H:%M:%S")
  local w
  w=$(get_term_width)

  echo ""
  echo -e "${DIM}$(hline)${NC}"
  echo -e "${BOLD}${CYAN}  🎬 E N S E M B L E   C A S T  —  T H E A T E R   M O D E${NC}"

  # プロジェクト情報
  local movie="—"
  local project="—"
  if [ -f "$PROJECT_PATH/dashboard.md" ]; then
    movie=$(grep -m1 '映画:' "$PROJECT_PATH/dashboard.md" 2>/dev/null | sed 's/.*映画: *//' || echo "—")
    project=$(grep -m1 'プロジェクト:' "$PROJECT_PATH/dashboard.md" 2>/dev/null | sed 's/.*プロジェクト: *//' || echo "—")
  fi
  echo -e "  ${DIM}🎞️ $movie  |  📁 $project  |  🕐 $TIMESTAMP${NC}"
  echo -e "${DIM}$(hline)${NC}"
}

# ========================================
# キャスト状況（コンパクト横並び）
# ========================================
show_cast_status() {
  echo -e "  ${WHITE}${BOLD}🎭 CAST${NC}"
  echo ""

  if [ ! -f "$PROJECT_PATH/cast/roster.yaml" ]; then
    echo -e "  ${DIM}(キャストなし)${NC}"
    return
  fi

  local slugs
  slugs=$(grep -E '^\s+-\s+slug:' "$PROJECT_PATH/cast/roster.yaml" 2>/dev/null | sed 's/.*slug: *//' | tr -d '"' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

  [ -z "$slugs" ] && { echo -e "  ${DIM}(キャストなし)${NC}"; return; }

  while IFS= read -r slug; do
    slug=$(echo "$slug" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_-]//g')
    [ -z "$slug" ] && continue
    get_char_info "$slug"

    local color="${CHAR_COLORS[$slug]}"
    local name="${CHAR_NAMES[$slug]}"
    local emoji="${CHAR_EMOJIS[$slug]}"

    # ステータス読み取り
    local state="待機" task="—" task_id="—"
    local icon="⬜"
    if [ -f "$PROJECT_PATH/logs/${slug}_status.txt" ]; then
      local status_line
      status_line=$(head -1 "$PROJECT_PATH/logs/${slug}_status.txt" 2>/dev/null || true)
      if [ -n "$status_line" ]; then
        state=$(echo "$status_line" | cut -d'|' -f1)
        task=$(echo "$status_line" | cut -d'|' -f2)
        task_id=$(echo "$status_line" | cut -d'|' -f3)
      fi
    fi

    case "$state" in
      "処理中"|"リサーチ中") icon="🟢" ;;
      "完了待機")            icon="🟡" ;;
      "blocked")             icon="🔴" ;;
      "起動中"|"着任中")     icon="🔵" ;;
      *)                     icon="⬜" ;;
    esac

    # タスク表示
    local task_display=""
    if [ "$task" != "—" ] && [ -n "$task" ]; then
      task_display=" → ${task_id} ${task}"
    fi

    printf "  %s ${color}%s %s${NC} ${DIM}%s${NC}%s\n" \
      "$icon" "$emoji" "$name" "$state" "$task_display"
  done <<< "$slugs"
  echo ""
}

# ========================================
# タスク進捗
# ========================================
show_task_progress() {
  echo -e "  ${WHITE}${BOLD}📊 PROGRESS${NC}"
  echo ""

  if [ ! -d "$PROJECT_PATH/queue/tasks" ]; then
    echo -e "  ${DIM}(タスクなし)${NC}"
    return
  fi

  local total=0 done_count=0 in_progress=0
  local task_lines=""

  for task_file in "$PROJECT_PATH/queue/tasks"/*.yaml; do
    [ -f "$task_file" ] || continue

    local slug
    slug=$(basename "$task_file" .yaml | sed 's/[^a-zA-Z0-9_-]//g')
    [ -z "$slug" ] && continue

    # タスク情報をパース（複数タスク対応）
    local current_id="" current_title="" current_status=""
    while IFS= read -r line; do
      line=$(echo "$line" | tr -d '\r')

      local tid
      tid=$(echo "$line" | sed -nE 's/^\s*-?\s*id:\s*(.+)/\1/p')
      if [ -n "$tid" ]; then
        # 前のタスクを出力
        if [ -n "$current_id" ]; then
          total=$((total + 1))
          local pct=0 pct_icon="⏳"
          case "$current_status" in
            "done"|"complete"|"merged"|"approved") pct=100; done_count=$((done_count + 1)); pct_icon="✅" ;;
            "in_progress"|"assigned")   pct=50; in_progress=$((in_progress + 1)); pct_icon="🔄" ;;
            "review"|"in_review")       pct=80; in_progress=$((in_progress + 1)); pct_icon="🔍" ;;
            "blocked")                  pct=25; pct_icon="🚫" ;;
            *)                          pct=0; pct_icon="⏳" ;;
          esac
          get_char_info "$slug"
          local bar
          bar=$(progress_bar "$pct" 15)
          task_lines+=$(printf "  %s #%-2s ${DIM}%s${NC} %3d%% ${CHAR_COLORS[$slug]}%s${NC}  %s\n" \
            "$pct_icon" "$current_id" "$bar" "$pct" "$slug" "$current_title")
          task_lines+=$'\n'
        fi
        current_id="$tid"
        current_title=""
        current_status=""
      fi

      local ttitle
      ttitle=$(echo "$line" | sed -nE 's/^\s*title:\s*"?([^"]*)"?/\1/p')
      [ -n "$ttitle" ] && current_title="$ttitle"

      local tstatus
      tstatus=$(echo "$line" | sed -nE 's/^\s*status:\s*(.+)/\1/p')
      [ -n "$tstatus" ] && current_status="$tstatus"
    done < "$task_file"

    # 最後のタスク
    if [ -n "$current_id" ]; then
      total=$((total + 1))
      local pct=0 pct_icon="⏳"
      case "$current_status" in
        "done"|"complete"|"merged"|"approved") pct=100; done_count=$((done_count + 1)); pct_icon="✅" ;;
        "in_progress"|"assigned")   pct=50; in_progress=$((in_progress + 1)); pct_icon="🔄" ;;
        "review"|"in_review")       pct=80; in_progress=$((in_progress + 1)); pct_icon="🔍" ;;
        "blocked")                  pct=25; pct_icon="🚫" ;;
        *)                          pct=0; pct_icon="⏳" ;;
      esac
      get_char_info "$slug"
      local bar
      bar=$(progress_bar "$pct" 15)
      task_lines+=$(printf "  %s #%-2s ${DIM}%s${NC} %3d%% ${CHAR_COLORS[$slug]}%s${NC}  %s\n" \
        "$pct_icon" "$current_id" "$bar" "$pct" "$slug" "$current_title")
      task_lines+=$'\n'
    fi
  done

  if [ "$total" -gt 0 ]; then
    # 全体進捗バー
    local overall_pct=0
    if [ "$total" -gt 0 ]; then
      overall_pct=$(( (done_count * 100) / total ))
    fi
    local overall_bar
    overall_bar=$(progress_bar "$overall_pct" 30)
    echo -e "  ${BOLD}${overall_bar}${NC} ${WHITE}${overall_pct}%${NC}  ${DIM}(${done_count}/${total} complete, ${in_progress} active)${NC}"
    echo ""
    echo -ne "$task_lines"
  else
    echo -e "  ${DIM}(タスクなし)${NC}"
  fi
  echo ""
}

# ========================================
# Git Worktree 状態
# ========================================
show_worktree_status() {
  # target_path を production.yaml から取得
  local target_path
  target_path=$(grep -m1 'target_path:' "$PROJECT_PATH/config/production.yaml" 2>/dev/null \
    | sed 's/.*target_path: *//' | tr -d '"' | tr -d "'" | tr -d '\r' \
    | sed 's/#.*//' | sed 's/[[:space:]]*$//')

  # null や空なら表示しない
  if [ -z "$target_path" ] || [ "$target_path" = "null" ]; then
    return
  fi

  # git worktree list（失敗時はエラー表示）
  local worktrees git_exit=0
  worktrees=$(git -C "$target_path" worktree list 2>&1) || git_exit=$?
  if [ "$git_exit" -ne 0 ]; then
    echo -e "  ${WHITE}${BOLD}🌳 WORKTREES${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠ git worktree list failed at ${target_path}${NC}"
    echo ""
    return
  fi
  [ -z "$worktrees" ] && return

  # worktree が main だけなら表示しない
  local wt_count
  wt_count=$(echo "$worktrees" | wc -l)
  [ "$wt_count" -le 1 ] && return

  echo -e "  ${WHITE}${BOLD}🌳 WORKTREES${NC}"
  echo ""

  # here-string で subshell 回避（キャッシュ保持 + CR サニタイズ）
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    local wt_path wt_branch
    wt_path=$(echo "$line" | awk '{print $1}')
    # [branch] or (detached HEAD) を抽出
    wt_branch=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
    if [ -z "$wt_branch" ]; then
      wt_branch=$(echo "$line" | sed -n 's/.*(\(.*\)).*/\1/p')
      [ -z "$wt_branch" ] && wt_branch="(unknown)"
    fi

    # main は薄く表示
    if [ "$wt_branch" = "main" ]; then
      printf "  ${DIM}📁 %-30s %s${NC}\n" "$wt_branch" "$wt_path"
      continue
    fi

    # Cast ブランチから slug を抽出
    local slug=""
    slug=$(echo "$wt_branch" | sed -n 's|cast/\([^/]*\)/.*|\1|p')

    # dirty チェック（壊れた worktree は警告表示）
    local dirty=""
    local git_status_out git_status_exit=0
    git_status_out=$(git -C "$wt_path" status --short 2>&1) || git_status_exit=$?
    if [ "$git_status_exit" -ne 0 ]; then
      dirty=" ${RED}(broken)${NC}"
    else
      local changes
      changes=$(echo "$git_status_out" | grep -c '.' || echo 0)
      if [ "$changes" -gt 0 ]; then
        dirty=" ${YELLOW}(${changes} changes)${NC}"
      fi
    fi

    # slug に対応するカラーとキャラ名
    local color="${CYAN}"
    local display_name="$wt_branch"
    if [ -n "$slug" ]; then
      slug=$(echo "$slug" | sed 's/[^a-zA-Z0-9_-]//g')
      get_char_info "$slug"
      if [ -n "${CHAR_NAMES[$slug]+x}" ]; then
        color="${CHAR_COLORS[$slug]}"
        display_name="${CHAR_EMOJIS[$slug]} ${CHAR_NAMES[$slug]} → ${wt_branch}"
      fi
    fi

    printf "  ${color}📁 %s${NC}%b\n" "$display_name" "$dirty"
    printf "     ${DIM}%s${NC}\n" "$wt_path"
  done <<< "$worktrees"
  echo ""
}

# ========================================
# フレームワークフィードバック
# ========================================
show_framework_feedback() {
  local fb_file="$PROJECT_PATH/queue/framework_feedback.yaml"
  [ -f "$fb_file" ] || return

  # open ステータスのフィードバックを数える
  local open_count
  open_count=$(grep -c 'status: open' "$fb_file" 2>/dev/null || echo 0)
  local total_count
  total_count=$(grep -c '^\s*- id: FB-' "$fb_file" 2>/dev/null || echo 0)

  # フィードバックがなければ非表示
  [ "$total_count" -eq 0 ] && return

  echo -e "  ${WHITE}${BOLD}🔧 FRAMEWORK FEEDBACK${NC}  ${DIM}(${open_count} open / ${total_count} total)${NC}"
  echo ""

  # open のフィードバックを表示
  local in_entry=false current_id="" current_reporter="" current_title="" current_cat="" current_impact="" current_status=""

  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')

    # id フィールド
    local fid
    fid=$(echo "$line" | sed -nE 's/^\s*-?\s*id:\s*(FB-[0-9]+).*/\1/p')
    if [ -n "$fid" ]; then
      # 前のエントリを出力
      if [ -n "$current_id" ] && [ "$current_status" = "open" ]; then
        local impact_color="${DIM}"
        case "$current_impact" in
          "high")   impact_color="${RED}" ;;
          "medium") impact_color="${YELLOW}" ;;
          "low")    impact_color="${DIM}" ;;
        esac
        printf "  ${DIM}%s${NC}  ${impact_color}%s${NC}  %s  ${DIM}by %s${NC}\n" \
          "$current_id" "$current_impact" "$current_title" "$current_reporter"
      fi
      current_id="$fid"
      current_reporter="" current_title="" current_cat="" current_impact="" current_status=""
    fi

    # 各フィールド
    local val
    val=$(echo "$line" | sed -nE 's/^\s*reporter:\s*(.+)/\1/p'); [ -n "$val" ] && current_reporter="$val"
    val=$(echo "$line" | sed -nE 's/^\s*title:\s*"?([^"]*)"?/\1/p'); [ -n "$val" ] && current_title="$val"
    val=$(echo "$line" | sed -nE 's/^\s*category:\s*(.+)/\1/p'); [ -n "$val" ] && current_cat="$val"
    val=$(echo "$line" | sed -nE 's/^\s*impact:\s*(.+)/\1/p'); [ -n "$val" ] && current_impact="$val"
    val=$(echo "$line" | sed -nE 's/^\s*status:\s*(.+)/\1/p'); [ -n "$val" ] && current_status="$val"
  done < "$fb_file"

  # 最後のエントリ
  if [ -n "$current_id" ] && [ "$current_status" = "open" ]; then
    local impact_color="${DIM}"
    case "$current_impact" in
      "high")   impact_color="${RED}" ;;
      "medium") impact_color="${YELLOW}" ;;
      "low")    impact_color="${DIM}" ;;
    esac
    printf "  ${DIM}%s${NC}  ${impact_color}%s${NC}  %s  ${DIM}by %s${NC}\n" \
      "$current_id" "$current_impact" "$current_title" "$current_reporter"
  fi
  echo ""
}

# ========================================
# 会話ストリーム（メイン）
# ========================================
show_conversation() {
  local max_lines="${1:-15}"

  echo -e "  ${WHITE}${BOLD}💬 LIVE${NC}"
  echo ""

  if [ ! -f "$PROJECT_PATH/logs/activity.log" ] || [ ! -s "$PROJECT_PATH/logs/activity.log" ]; then
    echo -e "  ${DIM}  (まだ会話はありません...)${NC}"
    echo ""
    return
  fi

  tail -"$max_lines" "$PROJECT_PATH/logs/activity.log" | tr -d '\r' | while IFS=$'\t' read -r timestamp actor event message; do
    [ -z "$timestamp" ] && continue
    actor=$(echo "$actor" | tr -d '\r\n\t ' )

    # タイムスタンプ → 時刻のみ
    local time_only
    time_only=$(echo "$timestamp" | sed 's/.*T//' | cut -c1-5)

    # アクターの表示名とカラー
    local display_name="$actor"
    local color="${DIM}"
    local emoji="🎭"

    case "$actor" in
      "DIRECTOR")
        display_name="Director"
        color="${RED}"
        emoji="🎬"
        ;;
      "PRODUCER")
        display_name="Producer"
        color="${MAGENTA}"
        emoji="🎬"
        ;;
      "LINE_PRODUCER"|"LP")
        display_name="Line Producer"
        color="${MAGENTA}"
        emoji="📋"
        ;;
      *)
        # Cast member（actorをサニタイズしてからアクセス）
        actor=$(echo "$actor" | sed 's/[^a-zA-Z0-9_-]//g')
        [ -z "$actor" ] && continue
        get_char_info "$actor"
        if [ -n "${CHAR_NAMES[$actor]+x}" ]; then
          display_name="${CHAR_NAMES[$actor]}"
          color="${CHAR_COLORS[$actor]}"
          emoji="${CHAR_EMOJIS[$actor]}"
        fi
        ;;
    esac

    # イベントタイプに応じた装飾
    local prefix=""
    case "$event" in
      "arrival")      prefix="✨ " ;;
      "task_assign")  prefix="📋 " ;;
      "task_start")   prefix="▶️ " ;;
      "task_done")    prefix="✅ " ;;
      "review_start") prefix="🔍 " ;;
      "review_done")  prefix="✅ " ;;
      "blocked")      prefix="🚫 " ;;
      "cast_start")   prefix="🎬 " ;;
      "escalation")   prefix="🚨 " ;;
      "chat")         prefix="💬 " ;;
      "progress")     prefix="⚡ " ;;
      "ability")      prefix="🌟 " ;;
      "research_done") prefix="📚 " ;;
      *)              prefix="" ;;
    esac

    # chat/progress/ability はキャラのセリフとして目立たせる
    case "$event" in
      "chat"|"progress"|"ability")
        printf "  ${DIM}%s${NC}  %s ${color}${BOLD}%s${NC}\n" \
          "$time_only" "$emoji" "$display_name"
        printf "       ${color}%s %s${NC}\n" "$prefix" "$message"
        ;;
      *)
        printf "  ${DIM}%s  %s %-10s │ %s%s${NC}\n" \
          "$time_only" "$emoji" "$display_name" "$prefix" "$message"
        ;;
    esac
  done
  echo ""
}

# ========================================
# フッター
# ========================================
show_footer() {
  local mode="${1:-readonly}"
  echo -e "${DIM}$(hline)${NC}"
  if [ "$mode" = "interactive" ]; then
    echo -ne "  ${YELLOW}🍿 Owner ▶${NC} "
  else
    echo -e "${DIM}  [Ctrl+C で終了]  ${NC}"
  fi
}

# ========================================
# Producerにメッセージ送信
# ========================================
send_to_producer() {
  local message="$1"
  local send_script="$PROJECT_PATH/scripts/send-message.sh"

  if [ -f "$send_script" ]; then
    bash "$send_script" --check-busy producer "$message" 2>/dev/null
    return $?
  fi

  # fallback: wake-agent.sh
  local pane_id
  pane_id=$(grep -E '^producer:' "$PROJECT_PATH/config/panes.yaml" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [ -n "$pane_id" ]; then
    bash "$PROJECT_PATH/scripts/wake-agent.sh" "$pane_id" "$message" 2>/dev/null
    return $?
  fi

  return 1
}

# ========================================
# メイン表示
# ========================================
show_theater() {
  local mode="${1:-readonly}"
  clear

  show_header

  # 上段: 会話ストリーム（メイン）
  show_conversation 15

  echo -e "${DIM}$(hline)${NC}"

  # 下段: キャスト状況 + タスク進捗 + Worktree + Feedback
  show_cast_status
  show_task_progress
  show_worktree_status
  show_framework_feedback

  show_footer "$mode"
}

# ========================================
# エントリポイント
# ========================================
case "${1:-}" in
  --watch)
    # 鑑賞モード（表示のみ、2秒更新）
    trap 'echo ""; echo -e "\033[2m🎬 幕引き — シアターモード終了\033[0m"; exit 0' INT
    while true; do
      show_theater "readonly"
      sleep 2
    done
    ;;
  --interactive)
    # インタラクティブモード（鑑賞 + Producer に話しかけられる）
    trap 'echo ""; echo -e "\033[2m🎬 幕引き — シアターモード終了\033[0m"; exit 0' INT
    LAST_SENT=""
    while true; do
      show_theater "interactive"

      # read -t 2: 2秒待ち、入力があればProducerに送信
      if read -t 2 -r user_input; then
        if [ -n "$user_input" ]; then
          LAST_SENT="$user_input"
          if send_to_producer "$user_input"; then
            # 送信成功 → 一瞬フィードバック表示
            echo -e "  ${GREEN}✓ 送信しました${NC}"
            sleep 1
          else
            echo -e "  ${RED}✗ 送信失敗（Producerがbusy？）${NC}"
            sleep 2
          fi
        fi
      fi
    done
    ;;
  *)
    # 1回表示
    show_theater "readonly"
    ;;
esac
