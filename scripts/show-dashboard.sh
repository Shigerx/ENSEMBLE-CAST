#!/usr/bin/env bash
# show-dashboard.sh — ダッシュボードをターミナルにカラー表示
# Usage: bash scripts/show-dashboard.sh
#        bash scripts/show-dashboard.sh --watch  (2秒ごとに自動更新)

set -euo pipefail

PROJECT_PATH="/mnt/c/Users/shige/antigravity/ENSEMBLE-CAST"
DASHBOARD="$PROJECT_PATH/dashboard.md"

if [ ! -f "$DASHBOARD" ]; then
  echo -e "\033[1;31m【錯】\033[0m dashboard.md が見つかりません: $DASHBOARD"
  exit 1
fi

display_dashboard() {
  clear
  echo -e "\033[1;33m╔══════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;33m║  🎬 ENSEMBLE CAST — DASHBOARD           ║\033[0m"
  echo -e "\033[1;33m╚══════════════════════════════════════════╝\033[0m"
  echo ""

  # dashboard.md をカラー変換して表示
  # - 🚨 見出し → 赤
  # - ✅ 見出し → 緑
  # - 🔄 見出し → 黄
  # - 🎯 見出し → マゼンタ
  # - その他 ## → シアン
  # - 引用 > → DIM
  # - トップレベル # → 白太字
  sed \
    -e 's/^## 🚨.*/\x1b[1;31m&\x1b[0m/' \
    -e 's/^## ✅.*/\x1b[1;32m&\x1b[0m/' \
    -e 's/^## 🔄.*/\x1b[1;33m&\x1b[0m/' \
    -e 's/^## 🎯.*/\x1b[1;35m&\x1b[0m/' \
    -e 's/^## ⏸️.*/\x1b[2m&\x1b[0m/' \
    -e 's/^## ❓.*/\x1b[1;36m&\x1b[0m/' \
    -e 's/^## .*/\x1b[1;36m&\x1b[0m/' \
    -e 's/^> .*/\x1b[2m&\x1b[0m/' \
    -e 's/^# .*/\x1b[1;37m&\x1b[0m/' \
    "$DASHBOARD"

  echo ""
  echo -e "\033[2m--- $(date '+%H:%M:%S') に表示 ---\033[0m"
}

if [ "${1:-}" = "--watch" ]; then
  trap 'echo ""; echo -e "\033[2m監視を終了しました\033[0m"; exit 0' INT
  while true; do
    display_dashboard
    sleep 2
  done
else
  display_dashboard
fi
