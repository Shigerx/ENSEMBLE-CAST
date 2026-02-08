#!/usr/bin/env bash
# =============================================================================
# snapshot-phase.sh — Phase完了時の素材スナップショット保存
#
# Phase中のactivity.log, dashboard.md, chronicles, reportsを
# episodes/ にアーカイブし、脚本生成素材(materials.yaml)も作成する。
#
# Usage:
#   bash scripts/snapshot-phase.sh <phase_number>
#
# Example:
#   bash scripts/snapshot-phase.sh 7
# =============================================================================
set -euo pipefail

PHASE="${1:?Usage: bash scripts/snapshot-phase.sh <phase_number>}"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EPISODE_DIR="${PROJECT_PATH}/episodes/phase${PHASE}"

# カラー
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

echo -e "${CYAN}[snapshot] Phase ${PHASE} のスナップショットを保存中...${NC}"

# ディレクトリ作成
mkdir -p "$EPISODE_DIR"

# 1. activity.log — Phase期間分を抽出してコピー
if [[ -f "${PROJECT_PATH}/logs/activity.log" ]]; then
  cp "${PROJECT_PATH}/logs/activity.log" "${EPISODE_DIR}/activity.log"
  echo -e "  ${GREEN}✓${NC} activity.log"
else
  echo -e "  ${YELLOW}⚠${NC} activity.log が見つかりません（スキップ）"
fi

# 2. dashboard.md — 現在の状態をスナップショット
if [[ -f "${PROJECT_PATH}/dashboard.md" ]]; then
  cp "${PROJECT_PATH}/dashboard.md" "${EPISODE_DIR}/dashboard.md"
  echo -e "  ${GREEN}✓${NC} dashboard.md"
else
  echo -e "  ${YELLOW}⚠${NC} dashboard.md が見つかりません（スキップ）"
fi

# 3. chronicles — 各キャストの行動履歴
CHRONICLES_DIR="${EPISODE_DIR}/chronicles"
mkdir -p "$CHRONICLES_DIR"
CHRONICLE_COUNT=0
for chronicle in "${PROJECT_PATH}"/cast/members/*/chronicle.yaml; do
  if [[ -f "$chronicle" ]]; then
    slug=$(basename "$(dirname "$chronicle")")
    cp "$chronicle" "${CHRONICLES_DIR}/${slug}.yaml"
    CHRONICLE_COUNT=$((CHRONICLE_COUNT + 1))
  fi
done
echo -e "  ${GREEN}✓${NC} chronicles (${CHRONICLE_COUNT}名分)"

# 4. reports — 各キャストのレポート
REPORTS_DIR="${EPISODE_DIR}/reports"
mkdir -p "$REPORTS_DIR"
REPORT_COUNT=0
for report in "${PROJECT_PATH}"/queue/reports/*_report.yaml; do
  if [[ -f "$report" ]]; then
    cp "$report" "${REPORTS_DIR}/$(basename "$report")"
    REPORT_COUNT=$((REPORT_COUNT + 1))
  fi
done
echo -e "  ${GREEN}✓${NC} reports (${REPORT_COUNT}件)"

# 5. collect-materials.py で脚本生成素材を作成
if [[ -f "${PROJECT_PATH}/scripts/collect-materials.py" ]]; then
  python3 "${PROJECT_PATH}/scripts/collect-materials.py" \
    --phase "$PHASE" \
    --base "$PROJECT_PATH" \
    --output "${EPISODE_DIR}/materials.yaml" 2>&1 | while read -r line; do
    echo -e "  ${DIM}${line}${NC}"
  done
  echo -e "  ${GREEN}✓${NC} materials.yaml"
else
  echo -e "  ${YELLOW}⚠${NC} collect-materials.py が見つかりません（スキップ）"
fi

# 6. タイムスタンプ記録
echo "phase: ${PHASE}" > "${EPISODE_DIR}/snapshot_meta.yaml"
echo "snapshot_at: \"$(date '+%Y-%m-%dT%H:%M:%S')\"" >> "${EPISODE_DIR}/snapshot_meta.yaml"
echo "files:" >> "${EPISODE_DIR}/snapshot_meta.yaml"
find "$EPISODE_DIR" -type f -not -name "snapshot_meta.yaml" -printf "  - %P\n" 2>/dev/null \
  | sort >> "${EPISODE_DIR}/snapshot_meta.yaml" || true

echo ""
echo -e "${GREEN}[snapshot] Phase ${PHASE} スナップショット完了${NC}"
echo -e "${DIM}  保存先: episodes/phase${PHASE}/${NC}"
echo ""
echo -e "${CYAN}脚本生成するには:${NC}"
echo -e "  ${DIM}Theater の Couch で「EP.${PHASE} の脚本書いて」と依頼${NC}"
echo -e "  ${DIM}または手動: episodes/phase${PHASE}/materials.yaml + scripts/screenplay-prompt.md を使用${NC}"
