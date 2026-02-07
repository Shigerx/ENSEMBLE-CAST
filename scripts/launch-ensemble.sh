#!/usr/bin/env bash
# =============================================================================
# ENSEMBLE-CAST v3 起動スクリプト
# scale: small → v2モード（Producer + Director + Cast）
# scale: large → v3モード（Producer + LP + Director×N + Cast×N）
# =============================================================================
set -euo pipefail

# =========================================================================
# ENSEMBLE_ROOT 解決
# =========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENSEMBLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PRODUCTION_YAML="$ENSEMBLE_ROOT/config/production.yaml"
UNITS_YAML="$ENSEMBLE_ROOT/config/units.yaml"
ROSTER_YAML="$ENSEMBLE_ROOT/cast/roster.yaml"
PANES_YAML="$ENSEMBLE_ROOT/config/panes.yaml"

SESSION_NAME="ensemble"

# =========================================================================
# ユーティリティ
# =========================================================================
log_info() {
  echo "[launch-ensemble] $1"
}

log_error() {
  echo "[launch-ensemble] ERROR: $1" >&2
}

die() {
  log_error "$1"
  exit 1
}

# =========================================================================
# 簡易 YAML 値取得（grep + sed、外部依存なし）
# =========================================================================

# トップレベルの "key: value" を取得
yaml_get_value() {
  local file="$1"
  local key="$2"
  grep -E "^${key}:" "$file" 2>/dev/null | sed -E 's/^[^:]+:\s*//' | sed -E 's/^["'"'"']|["'"'"']$//g' | tr -d '\r'
}

# roster.yaml から slug 一覧を取得
roster_get_slugs() {
  local file="$1"
  grep -E '^\s+-\s+slug:' "$file" 2>/dev/null | sed -E 's/.*slug:\s*"?([^"]+)"?.*/\1/' | tr -d '\r' || true
}

# roster.yaml から reviewer の slug を取得
roster_get_reviewer_slugs() {
  local file="$1"
  # is_reviewer: true の前の slug を取得（簡易実装）
  # roster.yaml の形式: slug, ..., is_reviewer: true が同一メンバーブロック内
  local in_member=""
  local current_slug=""
  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"
    if echo "$line" | grep -qE '^\s+-\s+slug:'; then
      current_slug="$(echo "$line" | sed -E 's/.*slug:\s*"?([^"]+)"?.*/\1/')"
      in_member="1"
    fi
    if [ -n "$in_member" ] && echo "$line" | grep -qE '^\s+is_reviewer:\s*true'; then
      echo "$current_slug"
      in_member=""
      current_slug=""
    fi
    # 新しいメンバーブロック開始でリセット
    if echo "$line" | grep -qE '^\s+-\s+slug:' && [ -n "$current_slug" ]; then
      in_member="1"
    fi
  done < "$file"
}

# =========================================================================
# ペイン作成ヘルパー
# =========================================================================

# 新しいペインを作成し、%IDを返す
# $1: ラベル（ペインタイトル）
# $2: PS1カラーコード（オプション）
create_pane() {
  local label="$1"
  local color="${2:-32}"  # デフォルト: 緑

  local pane_id
  pane_id=$(tmux split-window -t "$SESSION_NAME" -P -F '#{pane_id}' -c "$ENSEMBLE_ROOT")

  # ペインタイトル設定
  tmux select-pane -t "$pane_id" -T "$label"

  # tiled layout に再配置
  tmux select-layout -t "$SESSION_NAME" tiled

  # PS1 カスタマイズ
  tmux send-keys -t "$pane_id" "export PS1='(\033[1;${color}m${label}\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.3
  tmux send-keys -t "$pane_id" Enter

  echo "$pane_id"
}

# =========================================================================
# scale 判定
# =========================================================================
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

# =========================================================================
# scale: small（v2モード）
# =========================================================================
launch_small() {
  log_info "scale: small（v2モード）で起動します"

  # セッション作成（最初のペインが Producer）
  tmux new-session -d -s "$SESSION_NAME" -c "$ENSEMBLE_ROOT"
  local producer_pane
  producer_pane=$(tmux display-message -t "$SESSION_NAME" -p '#{pane_id}')

  tmux select-pane -t "$producer_pane" -T "producer"
  tmux send-keys -t "$producer_pane" "export PS1='(\033[1;35mproducer\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.3
  tmux send-keys -t "$producer_pane" Enter

  # Director ペイン作成
  local director_pane
  director_pane=$(create_pane "director" "33")

  # panes.yaml ヘッダー
  {
    echo "# ENSEMBLE CAST — ペインID管理"
    echo "# launch-ensemble.sh が生成。全エージェントが参照。"
    echo "# tmux固有ID（%N形式）はペイン追加・削除で変わらない。"
    echo "producer: \"$producer_pane\""
    echo "director: \"$director_pane\""
    echo "cast:"
  } > "$PANES_YAML"

  # Cast ペイン作成（roster.yaml から読み取り）
  if [ -f "$ROSTER_YAML" ]; then
    local reviewer_slugs
    reviewer_slugs=$(roster_get_reviewer_slugs "$ROSTER_YAML")

    while IFS= read -r slug; do
      [ -z "$slug" ] && continue

      local color="34"  # Cast: 青
      # Reviewer かどうかチェック
      if echo "$reviewer_slugs" | grep -qx "$slug"; then
        color="36"  # Reviewer: シアン
      fi

      local cast_pane
      cast_pane=$(create_pane "$slug" "$color")
      echo "  $slug: \"$cast_pane\"" >> "$PANES_YAML"

      # ステータスファイル初期化
      echo "起動中|—|—|$(date '+%Y-%m-%dT%H:%M:%S')" > "$ENSEMBLE_ROOT/logs/${slug}_status.txt"

      log_info "Cast ペイン作成: $slug ($cast_pane)"
    done <<< "$(roster_get_slugs "$ROSTER_YAML")"
  else
    log_info "警告: roster.yaml が見つかりません。Cast ペインは作成されません。"
  fi

  log_info "panes.yaml を更新しました"
}

# =========================================================================
# scale: large（v3マルチユニットモード）
# =========================================================================
launch_large() {
  log_info "scale: large（v3マルチユニットモード）で起動します"

  if [ ! -f "$UNITS_YAML" ]; then
    die "config/units.yaml が見つかりません。scale: large には units.yaml が必要です。"
  fi

  # セッション作成（最初のペインが Producer）
  tmux new-session -d -s "$SESSION_NAME" -c "$ENSEMBLE_ROOT"
  local producer_pane
  producer_pane=$(tmux display-message -t "$SESSION_NAME" -p '#{pane_id}')

  tmux select-pane -t "$producer_pane" -T "producer"
  tmux send-keys -t "$producer_pane" "export PS1='(\033[1;35mproducer\033[0m) \033[1;32m\w\033[0m\$ '"
  sleep 0.3
  tmux send-keys -t "$producer_pane" Enter

  # Line Producer ペイン作成
  local lp_pane
  lp_pane=$(create_pane "line_producer" "35")

  # panes.yaml ヘッダー
  {
    echo "# ENSEMBLE CAST — ペインID管理"
    echo "# launch-ensemble.sh が生成。全エージェントが参照。"
    echo "# tmux固有ID（%N形式）はペイン追加・削除で変わらない。"
    echo "producer: \"$producer_pane\""
    echo "line_producer: \"$lp_pane\""
    echo "units:"
  } > "$PANES_YAML"

  # units.yaml からユニット定義を読み取って各ユニットのペイン作成
  local current_unit=""
  local in_units=false
  local in_cast=false

  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"

    # コメント行・空行スキップ
    if echo "$line" | grep -qE '^\s*#|^\s*$'; then
      continue
    fi

    # units: セクション開始
    if echo "$line" | grep -qE '^units:\s*$'; then
      in_units=true
      continue
    fi

    # 別のトップレベルセクション開始 → units セクション終了
    if echo "$line" | grep -qE '^\S' && ! echo "$line" | grep -qE '^units:'; then
      in_units=false
      in_cast=false
      continue
    fi

    if [ "$in_units" = false ]; then
      continue
    fi

    # ユニット名（インデント2）
    local unit_name
    unit_name=$(echo "$line" | sed -nE 's/^  ([a-zA-Z_][a-zA-Z0-9_-]*):\s*$/\1/p')
    if [ -n "$unit_name" ]; then
      current_unit="$unit_name"
      in_cast=false

      # ユニットの Director ペイン作成
      local dir_pane
      dir_pane=$(create_pane "dir-${current_unit}" "33")

      echo "  $current_unit:" >> "$PANES_YAML"
      echo "    director: \"$dir_pane\"" >> "$PANES_YAML"
      echo "    cast:" >> "$PANES_YAML"

      log_info "ユニット '$current_unit' Director ペイン作成: $dir_pane"
      continue
    fi

    # cast セクション開始
    if echo "$line" | grep -qE '^\s{4}cast:\s*$'; then
      in_cast=true
      continue
    fi

    # cast アイテム（インラインオブジェクト）
    if [ "$in_cast" = true ]; then
      local cast_slug
      cast_slug=$(echo "$line" | sed -nE 's/.*slug:\s*([a-zA-Z_][a-zA-Z0-9_-]*).*/\1/p')
      if [ -n "$cast_slug" ]; then
        local cast_pane
        cast_pane=$(create_pane "$cast_slug" "34")
        echo "      $cast_slug: \"$cast_pane\"" >> "$PANES_YAML"

        # ステータスファイル初期化
        echo "起動中|—|—|$(date '+%Y-%m-%dT%H:%M:%S')" > "$ENSEMBLE_ROOT/logs/${cast_slug}_status.txt"

        log_info "ユニット '$current_unit' Cast ペイン作成: $cast_slug ($cast_pane)"
        continue
      fi

      # cast 配列外の行に遭遇 → cast セクション終了
      if echo "$line" | grep -qE '^\s{4}[a-zA-Z]'; then
        in_cast=false
      fi
    fi

  done < "$UNITS_YAML"

  log_info "panes.yaml を更新しました"
}

# =========================================================================
# Stage Manager 起動
# =========================================================================
launch_stage_manager() {
  local sm_dir="$ENSEMBLE_ROOT/scripts/stage-manager"
  local pid_file="$ENSEMBLE_ROOT/logs/stage_manager_pids.txt"

  # 前回のPIDファイルをクリア
  : > "$pid_file"

  # guard.js は pre-commit hook として動作するため、ここでは起動しない
  # （.githooks/pre-commit から呼ばれる）

  # router.js（存在する場合のみ）
  if [ -f "$sm_dir/router.js" ]; then
    log_info "Stage Manager: router.js を起動"
    node "$sm_dir/router.js" &
    echo $! >> "$pid_file"
  fi

  # checkpoint.js（存在する場合のみ）
  if [ -f "$sm_dir/checkpoint.js" ]; then
    log_info "Stage Manager: checkpoint.js を起動"
    node "$sm_dir/checkpoint.js" &
    echo $! >> "$pid_file"
  fi

  # health.js（存在する場合のみ）
  if [ -f "$sm_dir/health.js" ]; then
    log_info "Stage Manager: health.js を起動"
    node "$sm_dir/health.js" &
    echo $! >> "$pid_file"
  fi

  log_info "Stage Manager PIDs: $(cat "$pid_file" | tr '\n' ' ')"
}

# =========================================================================
# メイン
# =========================================================================
main() {
  log_info "ENSEMBLE-CAST 起動開始"
  log_info "プロジェクトルート: $ENSEMBLE_ROOT"

  # production.yaml の存在確認
  if [ ! -f "$PRODUCTION_YAML" ]; then
    die "config/production.yaml が見つかりません"
  fi

  # 既存セッションのチェック
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    die "tmux セッション '$SESSION_NAME' は既に存在します。先に終了してください: tmux kill-session -t $SESSION_NAME"
  fi

  # scale 判定
  local scale
  scale=$(get_scale)
  log_info "scale: $scale"

  # scale に応じた起動
  case "$scale" in
    small)
      launch_small
      ;;
    large)
      launch_large
      ;;
    *)
      die "不明な scale: $scale（small または large を指定してください）"
      ;;
  esac

  # Stage Manager 起動
  launch_stage_manager

  # git hooks 設定（guard.js を pre-commit として登録）
  local hooks_dir="$ENSEMBLE_ROOT/.githooks"
  if [ -d "$hooks_dir" ] && [ -f "$hooks_dir/pre-commit" ]; then
    git -C "$ENSEMBLE_ROOT" config core.hooksPath .githooks 2>/dev/null || true
    log_info "git hooks パスを .githooks に設定"
  fi

  log_info "起動完了。tmux attach-session -t $SESSION_NAME でアタッチしてください。"
}

main "$@"
