#!/usr/bin/env bash
# guard.sh — 破壊的コマンドブロッカー
# PreToolUse hookとして実行される
# stdinからJSON（tool_input）を受け取り、危険なコマンドをブロックする
# exit 0 = 許可, exit 2 = ブロック

set -euo pipefail

# stdinからJSONを読み取り
INPUT=$(cat)

# tool_inputからcommandフィールドを抽出（jq未インストール時のフォールバック）
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# commandが空なら許可（Bash以外のツール）
if [ -z "$COMMAND" ]; then
  exit 0
fi

# ブロック対象パターン（正規表現）
BLOCKED_PATTERNS=(
  'rm\s+-rf\s+/'
  'rm\s+-rf\s+/\*'
  'rm\s+-fr\s+/'
  'rm\s+-fr\s+/\*'
  'sudo\s+'
  'chmod\s+777'
  'git\s+push\s+--force\s+(origin\s+)?main'
  'git\s+push\s+-f\s+(origin\s+)?main'
  'DROP\s+TABLE'
  'DROP\s+DATABASE'
  'tmux\s+kill-server'
  'tmux\s+kill-session\s+-t\s+ensemble'
  '>\s*/dev/sda'
  'mkfs\.'
  'dd\s+if=.+of=/dev/'
  ':(){ :|:& };:'
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED by guard.sh: command matches dangerous pattern '$pattern'" >&2
    echo "Command was: $COMMAND" >&2
    exit 2
  fi
done

# パターンに一致しなければ許可
exit 0
