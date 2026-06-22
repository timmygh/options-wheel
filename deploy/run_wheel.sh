#!/usr/bin/env bash
# Wrapper for the options-wheel strategy, designed to be cron-safe.
# - Uses absolute paths (cron has a minimal environment).
# - Cancels any stale/foreign OPEN orders before running (the wheel uses
#   market orders that fill immediately, so it should never have resting orders;
#   a leftover order can fill mid-wheel and inject an odd-lot that crashes
#   update_state()). See project note "Finding 3".
# - Captures all stdout/stderr to a dated log so we keep a record even if the
#   strategy crashes before writing its own JSON log ("Finding 2").
# - Writes a clear OK/FAILED status line for monitoring.
#
# Usage: run_wheel.sh [extra run-strategy flags...]
#   e.g. run_wheel.sh --fresh-start    (first run only)

set -uo pipefail

PROJECT_DIR="/home/want/my-obsidian-vault/timmy/06 Projects/claude.alpaca.paper"
REPO_DIR="$PROJECT_DIR/options-wheel"
VENV_BIN="$REPO_DIR/.venv/bin"
LOG_DIR="$REPO_DIR/logs"
ENV_FILE="$REPO_DIR/.env"

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
RUN_LOG="$LOG_DIR/wheel_${STAMP}.log"
STATUS_LOG="$LOG_DIR/wheel_status.log"   # one appended line per run
ALERT_MD="$PROJECT_DIR/WHEEL ALERTS.md"  # Obsidian-visible failure log
PS_EXE="/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# Notify on failure: (1) durable append to an Obsidian note, (2) best-effort Windows toast.
notify_failure() {
  local reason="$1"
  local human; human="$(date '+%Y-%m-%d %H:%M %Z')"
  if [[ ! -f "$ALERT_MD" ]]; then
    printf '# ⚠️ Wheel Alerts\n\nAuto-appended by `run_wheel.sh` when a scheduled run fails. Clear entries once reviewed.\n\n' > "$ALERT_MD"
  fi
  echo "- **$human** — wheel run FAILED ($reason). Run log: \`$RUN_LOG\`" >> "$ALERT_MD"
  if [[ -x "$PS_EXE" ]]; then
    "$PS_EXE" -NoProfile -ExecutionPolicy Bypass -Command "
\$ErrorActionPreference='SilentlyContinue';
\$AppId='{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe';
[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]|Out-Null;
\$t=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);
\$x=\$t.GetElementsByTagName('text');
\$x.Item(0).AppendChild(\$t.CreateTextNode('Options-Wheel run FAILED'))|Out-Null;
\$x.Item(1).AppendChild(\$t.CreateTextNode('$reason - check wheel_status.log'))|Out-Null;
\$n=[Windows.UI.Notifications.ToastNotification]::new(\$t);
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$AppId).Show(\$n);
" >/dev/null 2>&1 || true
  fi
}

{
  log "=== wheel run start (args: $*) ==="

  # --- Load credentials from .env ---
  if [[ ! -f "$ENV_FILE" ]]; then
    log "ERROR: .env not found at $ENV_FILE"
    echo "$STAMP FAILED no-env" >> "$STATUS_LOG"
    notify_failure "no .env file"
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a

  if [[ "${IS_PAPER:-true}" == "true" ]]; then
    API_BASE="https://paper-api.alpaca.markets"
  else
    API_BASE="https://api.alpaca.markets"
  fi

  # --- Pre-flight: cancel all open orders ---
  log "Pre-flight: cancelling any open orders on $API_BASE ..."
  CANCEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API_BASE/v2/orders" \
    -H "APCA-API-KEY-ID: ${ALPACA_API_KEY}" \
    -H "APCA-API-SECRET-KEY: ${ALPACA_SECRET_KEY}")
  log "Pre-flight cancel HTTP $CANCEL_CODE"

  # --- Run the strategy ---
  log "Running run-strategy ..."
  "$VENV_BIN/run-strategy" --strat-log --log-level INFO "$@"
  RC=$?
  log "run-strategy exited with code $RC"

  if [[ $RC -eq 0 ]]; then
    echo "$STAMP OK" >> "$STATUS_LOG"
  else
    echo "$STAMP FAILED rc=$RC (see $RUN_LOG)" >> "$STATUS_LOG"
    notify_failure "rc=$RC"
  fi
  log "=== wheel run end (rc=$RC) ==="
  exit $RC
} >> "$RUN_LOG" 2>&1
