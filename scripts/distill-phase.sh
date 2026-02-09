#!/usr/bin/env bash
# =============================================================================
# distill-phase.sh — Phase 完了時にチームナレッジを蒸留する
#
# Usage:
#   bash scripts/distill-phase.sh <phase_number>
#
# 機能:
#   1. episodes/phase{N}/ の activity.log, chronicles, reports, design を読み込み
#   2. 蒸留ソースの一覧を出力する
#   3. Director が Task tool（Haiku モデル推奨）で知見を抽出し、
#      memory/team_knowledge/ の各ファイルに追記する
#
# 前提:
#   - scripts/snapshot-phase.sh で Phase スナップショットが保存済み
#   - Director が Claude Code 内から実行する（Task tool を使うため）
#
# 注意:
#   このスクリプトは「何を蒸留すべきか」のソースファイル一覧を出力する。
#   実際の蒸留（AI による知見抽出）は Director が Task tool で行う。
#   スクリプト自体は非LLM（bash）で判断ロジックを持たない。
# =============================================================================
set -euo pipefail

PHASE="${1:?Usage: distill-phase.sh <phase_number>}"
ENSEMBLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EPISODE_DIR="${ENSEMBLE_ROOT}/episodes/phase${PHASE}"
KNOWLEDGE_DIR="${ENSEMBLE_ROOT}/memory/team_knowledge"

# カラー
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

# === Phase スナップショットの存在確認 ===
if [ ! -d "${EPISODE_DIR}" ]; then
  echo -e "${YELLOW}ERROR: ${EPISODE_DIR} が見つかりません。${NC}" >&2
  echo "先に snapshot-phase.sh を実行してください:" >&2
  echo "  bash scripts/snapshot-phase.sh ${PHASE}" >&2
  exit 1
fi

# === team_knowledge ディレクトリの存在確認 ===
mkdir -p "${KNOWLEDGE_DIR}"

echo -e "${CYAN}=== Phase ${PHASE} 蒸留ソース ===${NC}"
echo ""

echo -e "${GREEN}--- activity.log ---${NC}"
if [ -f "${EPISODE_DIR}/activity.log" ]; then
  echo "  ${EPISODE_DIR}/activity.log"
else
  echo -e "  ${DIM}(なし)${NC}"
fi

echo ""
echo -e "${GREEN}--- chronicles ---${NC}"
if [ -d "${EPISODE_DIR}/chronicles" ]; then
  find "${EPISODE_DIR}/chronicles" -name "*.yaml" -type f 2>/dev/null | sort | while read -r f; do
    echo "  ${f}"
  done
  CHRONICLE_COUNT=$(find "${EPISODE_DIR}/chronicles" -name "*.yaml" -type f 2>/dev/null | wc -l)
  if [ "${CHRONICLE_COUNT}" -eq 0 ]; then
    echo -e "  ${DIM}(なし)${NC}"
  fi
else
  echo -e "  ${DIM}(なし)${NC}"
fi

echo ""
echo -e "${GREEN}--- reports ---${NC}"
if [ -d "${EPISODE_DIR}/reports" ]; then
  find "${EPISODE_DIR}/reports" -name "*.yaml" -type f 2>/dev/null | sort | while read -r f; do
    echo "  ${f}"
  done
  REPORT_COUNT=$(find "${EPISODE_DIR}/reports" -name "*.yaml" -type f 2>/dev/null | wc -l)
  if [ "${REPORT_COUNT}" -eq 0 ]; then
    echo -e "  ${DIM}(なし)${NC}"
  fi
else
  echo -e "  ${DIM}(なし)${NC}"
fi

echo ""
echo -e "${GREEN}--- design debates ---${NC}"
if [ -d "${EPISODE_DIR}/design" ]; then
  find "${EPISODE_DIR}/design" -name "*_final.yaml" -type f 2>/dev/null | sort | while read -r f; do
    echo "  ${f}"
  done
  DESIGN_COUNT=$(find "${EPISODE_DIR}/design" -name "*_final.yaml" -type f 2>/dev/null | wc -l)
  if [ "${DESIGN_COUNT}" -eq 0 ]; then
    echo -e "  ${DIM}(なし)${NC}"
  fi
else
  # fallback: queue/design/ から直接
  if ls "${ENSEMBLE_ROOT}/queue/design/"*_final.yaml 1>/dev/null 2>&1; then
    for f in "${ENSEMBLE_ROOT}/queue/design/"*_final.yaml; do
      echo "  ${f}"
    done
  else
    echo -e "  ${DIM}(なし)${NC}"
  fi
fi

echo ""
echo -e "${GREEN}--- discussion (resolved/escalated) ---${NC}"
if [ -d "${EPISODE_DIR}/discussion" ]; then
  find "${EPISODE_DIR}/discussion" -name "*.yaml" -type f 2>/dev/null | sort | while read -r f; do
    echo "  ${f}"
  done
  DISC_COUNT=$(find "${EPISODE_DIR}/discussion" -name "*.yaml" -type f 2>/dev/null | wc -l)
  if [ "${DISC_COUNT}" -eq 0 ]; then
    echo -e "  ${DIM}(なし)${NC}"
  fi
else
  # fallback: queue/discussion/ から直接
  if [ -d "${ENSEMBLE_ROOT}/queue/discussion" ]; then
    DISC_COUNT=$(find "${ENSEMBLE_ROOT}/queue/discussion" -name "*.yaml" -type f 2>/dev/null | wc -l)
    if [ "${DISC_COUNT}" -gt 0 ]; then
      find "${ENSEMBLE_ROOT}/queue/discussion" -name "*.yaml" -type f 2>/dev/null | sort | while read -r f; do
        echo "  ${f}"
      done
    else
      echo -e "  ${DIM}(なし)${NC}"
    fi
  else
    echo -e "  ${DIM}(なし)${NC}"
  fi
fi

echo ""
echo -e "${CYAN}=== 蒸留手順 ===${NC}"
echo "Director は上記ファイルを Task tool（Haiku モデル推奨）に渡し、"
echo "以下のファイルに知見を追記してください:"
echo "  - ${KNOWLEDGE_DIR}/patterns.yaml"
echo "  - ${KNOWLEDGE_DIR}/anti_patterns.yaml"
echo "  - ${KNOWLEDGE_DIR}/decisions.yaml"
echo "  - ${KNOWLEDGE_DIR}/retrospective.yaml"
echo ""
echo -e "${DIM}Task tool プロンプト例:${NC}"
echo -e "${DIM}  以下のファイルから Phase ${PHASE} の知見を抽出し、${NC}"
echo -e "${DIM}  memory/team_knowledge/ の各ファイルに追記してください。${NC}"
echo -e "${DIM}  各ファイルの既存エントリの ID を確認し、次の連番で追加してください。${NC}"
