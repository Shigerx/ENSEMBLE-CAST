#!/usr/bin/env bash
# send-message.sh — 通信抽象化レイヤー
# tmux send-keys を抽象化し、将来の Agent Teams API 移行に備える。
#
# Usage: bash scripts/send-message.sh [--check-busy] <target> <message>
#   target: ペインID（%N形式）または slug名（producer, director, botan 等）
#   message: 送信テキスト
#
# 環境変数:
#   ENSEMBLE_ROOT: プロジェクトルート（未設定時はスクリプト位置から推定）
#   SEND_MESSAGE_DRY_RUN: "1" で tmux 実行をスキップ（テスト用）
#
# Exit codes:
#   0: 成功
#   1: 引数エラー / slug解決失敗 / pane不存在
#   2: Busy timeout（--check-busy 使用時）

set -euo pipefail

# =========================================================================
# 通信バックエンド設定
# 将来 Agent Teams API に移行する際はここを差し替える
# =========================================================================
BACKEND="tmux"  # "tmux" | "agent-teams" (将来)

# =========================================================================
# ENSEMBLE_ROOT 解決
# =========================================================================
if [ -z "${ENSEMBLE_ROOT:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ENSEMBLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

PANES_YAML="$ENSEMBLE_ROOT/config/panes.yaml"

# =========================================================================
# Usage
# =========================================================================
usage() {
  echo "Usage: bash scripts/send-message.sh [--check-busy] <target> <message>" >&2
  echo "  target:  ペインID（%N形式）または slug名" >&2
  echo "  message: 送信テキスト" >&2
  echo "  --check-busy: 送信前にIdle確認（最大3回、30秒間隔）" >&2
  exit 1
}

# =========================================================================
# panes.yaml から slug → %ID を解決
# grep + sed でパース（外部依存なし）
# =========================================================================
resolve_slug() {
  local slug="$1"
  local pane_id=""

  # slug バリデーション（正規表現インジェクション防止）
  if [[ ! "$slug" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "エラー: 不正な slug 形式: $slug" >&2
    return 1
  fi

  if [ ! -f "$PANES_YAML" ]; then
    echo "エラー: panes.yaml が見つかりません: $PANES_YAML" >&2
    return 1
  fi

  # トップレベルキー: "slug: \"%N\""
  # 例: director: "%1"
  pane_id=$(grep -E "^${slug}:" "$PANES_YAML" | sed -E 's/^[^"]*"([^"]+)".*/\1/' || true)

  if [ -n "$pane_id" ]; then
    echo "$pane_id"
    return 0
  fi

  # cast セクション内: "  slug: \"%N\""
  # 例:   botan: "%2"
  pane_id=$(grep -E "^  ${slug}:" "$PANES_YAML" | sed -E 's/^[^"]*"([^"]+)".*/\1/' || true)

  if [ -n "$pane_id" ]; then
    echo "$pane_id"
    return 0
  fi

  echo "エラー: slug \"${slug}\" が panes.yaml に見つかりません" >&2
  return 1
}

# =========================================================================
# Busy/Idle チェック
# tmux capture-pane で最後の20行を確認
# =========================================================================
BUSY_PATTERNS="thinking|Effecting|Boondoggling|Puzzling|Calculating|Fermenting|Crunching|Esc to interrupt"
IDLE_PATTERNS="❯ |bypass permissions on"

check_busy() {
  local pane_id="$1"
  local attempt

  for attempt in 1 2 3; do
    local output
    output=$(tmux capture-pane -t "$pane_id" -p | tail -20 2>/dev/null || true)

    # Idle チェック（プロンプトが表示されていれば送信OK）
    if echo "$output" | grep -qE "$IDLE_PATTERNS"; then
      return 0
    fi

    # Busy チェック
    if echo "$output" | grep -qE "$BUSY_PATTERNS"; then
      if [ "$attempt" -lt 3 ]; then
        sleep 30
      fi
      continue
    fi

    # パターンにマッチしない → Idle扱い
    return 0
  done

  echo "エラー: $pane_id は3回チェックしてもBusy状態です" >&2
  return 2
}

# =========================================================================
# tmux バックエンドで送信（2コール send-keys ルール厳守）
# =========================================================================
send_via_tmux() {
  local pane_id="$1"
  local message="$2"

  # コール1: テキスト送信
  tmux send-keys -t "$pane_id" "$message"

  # 待機
  sleep 0.5

  # コール2: Enter送信
  tmux send-keys -t "$pane_id" Enter
}

# =========================================================================
# dry-run モード（テスト用）
# 実際の tmux コマンドの代わりに、実行されるはずのコマンドを出力
# =========================================================================
send_dry_run() {
  local pane_id="$1"
  local message="$2"
  local check_busy="$3"

  echo "[dry-run] target: $pane_id"
  echo "[dry-run] message: $message"
  if [ "$check_busy" = "true" ]; then
    echo "[dry-run] check-busy: enabled"
  fi
  echo "[dry-run] tmux send-keys -t \"$pane_id\" \"$message\""
  echo "[dry-run] sleep 0.5"
  echo "[dry-run] tmux send-keys -t \"$pane_id\" Enter"
}

# =========================================================================
# メイン
# =========================================================================
main() {
  local check_busy="false"
  local target=""
  local message=""

  # 引数パース
  while [ $# -gt 0 ]; do
    case "$1" in
      --check-busy)
        check_busy="true"
        shift
        ;;
      *)
        if [ -z "$target" ]; then
          target="$1"
        elif [ -z "$message" ]; then
          message="$1"
        fi
        shift
        ;;
    esac
  done

  # 引数チェック
  if [ -z "$target" ] || [ -z "$message" ]; then
    usage
  fi

  # target が %N 形式かどうかを判定
  local pane_id
  if [[ "$target" =~ ^%[0-9]+$ ]]; then
    # %ID 直接指定
    pane_id="$target"
  else
    # slug名 → %ID 解決
    pane_id=$(resolve_slug "$target") || exit 1
  fi

  # dry-run モード
  if [ "${SEND_MESSAGE_DRY_RUN:-}" = "1" ]; then
    send_dry_run "$pane_id" "$message" "$check_busy"
    exit 0
  fi

  # Busy/Idle チェック（オプション）
  if [ "$check_busy" = "true" ]; then
    check_busy "$pane_id" || exit $?
  fi

  # バックエンド選択
  case "$BACKEND" in
    tmux)
      send_via_tmux "$pane_id" "$message"
      ;;
    agent-teams)
      # 将来実装: Agent Teams API 経由で送信
      echo "エラー: agent-teams バックエンドは未実装です" >&2
      exit 1
      ;;
    *)
      echo "エラー: 不明なバックエンド: $BACKEND" >&2
      exit 1
      ;;
  esac
}

main "$@"
