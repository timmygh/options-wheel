#!/usr/bin/env bash
# Cron-safe wrapper for wheel_report.py — writes a dated Markdown report into <project>/reports/.
# Paths derived from this script's location (repo-portable).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PY="$REPO_DIR/.venv/bin/python"
LOG="$REPO_DIR/logs/report.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] running wheel_report.py"
  "$PY" "$SCRIPT_DIR/wheel_report.py" >/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] report rc=$?"
} >> "$LOG" 2>&1
