#!/usr/bin/env bash
# show-live.sh — ENSEMBLE CAST RPG風ライブモニター
#
# Usage:
#   bash scripts/show-live.sh           # 1回表示
#   bash scripts/show-live.sh --watch   # 2秒ごと自動更新

set -euo pipefail

PROJECT_PATH="/mnt/c/Users/shige/antigravity/ENSEMBLE-CAST"

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

# 状態アイコン
ICON_ACTIVE="🟢"
ICON_WAITING="🟡"
ICON_BLOCKED="🔴"
ICON_DONE="✅"
ICON_PROGRESS="🔄"
ICON_WARNING="⚠️"
ICON_PENDING="⏳"

# ========================================
# 表示関数
# ========================================
show_monitor() {
  local TIMESTAMP=$(date "+%H:%M:%S")

  # ヘッダー
  echo -e "${CYAN}${BOLD}"
  echo "🎬 ENSEMBLE CAST — ライブモニター                    ${TIMESTAMP}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${NC}"

  # キャスト状況テーブル
  echo -e "${WHITE}🎭 キャスト状況${NC}"
  echo "┌──────────┬──────────────┬──────────┬─────────────────────────────────┐"
  echo "│ キャスト │ ロール       │ 状態     │ 現在のタスク                    │"
  echo "├──────────┼──────────────┼──────────┼─────────────────────────────────┤"

  # roster.yamlからキャスト情報を読み取り
  if [ -f "$PROJECT_PATH/cast/roster.yaml" ]; then
    local members=$(grep -E "^\s+- slug:" "$PROJECT_PATH/cast/roster.yaml" 2>/dev/null | sed 's/.*slug: *//' | tr -d '"' || true)

    if [ -n "$members" ]; then
      while IFS= read -r slug; do
        [ -z "$slug" ] && continue

        # persona.yamlからdev_roleを取得
        local dev_role="—"
        if [ -f "$PROJECT_PATH/cast/members/$slug/persona.yaml" ]; then
          dev_role=$(grep -m1 "dev_role:" "$PROJECT_PATH/cast/members/$slug/persona.yaml" 2>/dev/null | sed 's/.*dev_role: *//' | tr -d '"' || echo "—")
        fi

        # status.txtから現在の状態を取得
        local state="—"
        local task="—"
        local task_id="—"
        local icon="$ICON_WAITING"

        if [ -f "$PROJECT_PATH/logs/${slug}_status.txt" ]; then
          local status_line=$(cat "$PROJECT_PATH/logs/${slug}_status.txt" 2>/dev/null | head -1)
          if [ -n "$status_line" ]; then
            state=$(echo "$status_line" | cut -d'|' -f1)
            task=$(echo "$status_line" | cut -d'|' -f2)
            task_id=$(echo "$status_line" | cut -d'|' -f3)
          fi
        fi

        # 状態に応じたアイコン
        case "$state" in
          "処理中") icon="$ICON_ACTIVE" ;;
          "リサーチ中") icon="$ICON_ACTIVE" ;;
          "完了待機") icon="$ICON_WAITING" ;;
          "blocked") icon="$ICON_BLOCKED" ;;
          "起動中") icon="$ICON_PENDING" ;;
          *) icon="$ICON_WAITING" ;;
        esac

        # タスク表示の整形
        local task_display="—"
        if [ "$task" != "—" ] && [ -n "$task" ]; then
          if [ "$task_id" != "—" ] && [ -n "$task_id" ]; then
            task_display="$task_id $task"
          else
            task_display="$task"
          fi
        fi

        # 長すぎる場合は切り詰め
        task_display=$(echo "$task_display" | cut -c1-30)

        printf "│ %s %-6s │ %-12s │ %-8s │ %-31s │\n" \
          "$icon" "$slug" "$dev_role" "$state" "$task_display"
      done <<< "$members"
    else
      echo "│ (キャストなし)                                                      │"
    fi
  else
    echo "│ (roster.yaml なし)                                                   │"
  fi

  echo "└──────────┴──────────────┴──────────┴─────────────────────────────────┘"
  echo ""

  # タスクフロー
  echo -e "${WHITE}📋 タスクフロー${NC}"

  # 各キャストのタスクを表示
  if [ -d "$PROJECT_PATH/queue/tasks" ]; then
    local has_tasks=false
    for task_file in "$PROJECT_PATH/queue/tasks"/*.yaml; do
      [ -f "$task_file" ] || continue
      has_tasks=true

      local slug=$(basename "$task_file" .yaml)

      # タスク情報を抽出
      local task_id=$(grep -m1 "id:" "$task_file" 2>/dev/null | head -1 | sed 's/.*id: *//' || echo "?")
      local task_title=$(grep -m1 "title:" "$task_file" 2>/dev/null | head -1 | sed 's/.*title: *//' | tr -d '"' || echo "Unknown")
      local task_status=$(grep -m1 "status:" "$task_file" 2>/dev/null | head -1 | sed 's/.*status: *//' || echo "pending")

      # ステータスアイコン
      local status_icon="[ ]"
      case "$task_status" in
        "done"|"complete") status_icon="[x]" ;;
        "in_progress") status_icon="[~]" ;;
        "blocked") status_icon="[!]" ;;
        *) status_icon="[ ]" ;;
      esac

      # 進捗アイコン
      local progress_icon="$ICON_PENDING"
      case "$task_status" in
        "done"|"complete") progress_icon="$ICON_DONE" ;;
        "in_progress") progress_icon="$ICON_PROGRESS" ;;
        "blocked") progress_icon="$ICON_WARNING blocked" ;;
        *) progress_icon="$ICON_PENDING" ;;
      esac

      printf "  %s #%s %-30s → %s %s\n" "$status_icon" "$task_id" "$task_title" "$slug" "$progress_icon"
    done

    if [ "$has_tasks" = false ]; then
      echo "  (タスクなし)"
    fi
  else
    echo "  (タスクディレクトリなし)"
  fi
  echo ""

  # アクティビティログ（最新20件）
  echo -e "${WHITE}📜 アクティビティログ（最新20件）${NC}"

  if [ -f "$PROJECT_PATH/logs/activity.log" ] && [ -s "$PROJECT_PATH/logs/activity.log" ]; then
    # 最新20件を逆順で表示
    tail -20 "$PROJECT_PATH/logs/activity.log" | tac | while IFS=$'\t' read -r timestamp actor event message; do
      [ -z "$timestamp" ] && continue

      # タイムスタンプから時刻だけ抽出
      local time_only=$(echo "$timestamp" | sed 's/.*T//' | cut -c1-5)

      # アクターアイコン
      local actor_icon="🎭"
      if [ "$actor" = "DIRECTOR" ]; then
        actor_icon="🎬"
      fi

      printf "  %s %s %-10s │ %s\n" "$time_only" "$actor_icon" "$actor" "$message"
    done
  else
    echo "  (ログなし)"
  fi
  echo ""
}

# ========================================
# メイン
# ========================================
if [ "${1:-}" = "--watch" ]; then
  # 2秒ごと自動更新モード
  while true; do
    clear
    show_monitor
    echo -e "${DIM}[Ctrl+C で終了]${NC}"
    sleep 2
  done
else
  # 1回表示モード
  show_monitor
fi
