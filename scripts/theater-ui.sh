#!/usr/bin/env bash
# ENSEMBLE CAST — Theater Web UI 起動
# Usage: bash scripts/theater-ui.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PORT=3939

echo -e "\033[33m🎬 ENSEMBLE CAST — Theater\033[0m"

# Start server
python3 "$SCRIPT_DIR/theater-server.py" --port "$PORT" --base "$BASE_DIR" &
SERVER_PID=$!

# Cleanup on exit
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  echo -e "\n\033[33m🎬 Theater closed.\033[0m"
}
trap cleanup EXIT INT TERM

# Wait for port
for i in $(seq 1 10); do
  if curl -s "http://localhost:$PORT/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

URL="http://localhost:$PORT"
echo "   $URL"

# Open browser (WSL → Windows browser)
if command -v wslview >/dev/null 2>&1; then
  wslview "$URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" 2>/dev/null || true
elif command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "$URL" 2>/dev/null || true
fi

echo "   Ctrl+C to stop"
wait "$SERVER_PID"
