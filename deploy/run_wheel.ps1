<#
  run_wheel.ps1 - Windows-native wrapper for the options-wheel strategy.
  PowerShell port of deploy/run_wheel.sh. Triggered by Windows Task Scheduler.

  - Paths are derived from this script's location (repo-portable):
      ScriptDir = <repo>\deploy, RepoDir = <repo>, ProjectDir = <repo>\..
  - The Python venv lives OUTSIDE the (synced) vault, at
      %LOCALAPPDATA%\options-wheel\.venv   (so it never collides with the WSL
      .venv in the synced folder, and a heavy venv is never synced).
  - Cancels any stale/foreign OPEN orders before running (the wheel uses market
    orders that fill immediately, so a leftover order can fill mid-wheel and
    inject an odd-lot that crashes update_state() - see project note "Finding 3").
  - Captures all output to a dated log so we keep a record even if the strategy
    crashes before writing its own JSON log ("Finding 2").
  - Writes a clear OK/FAILED status line, and on failure alerts via an
    Obsidian-visible note + a best-effort Windows toast.

  Usage: run_wheel.ps1 [extra run-strategy flags...]
    e.g. run_wheel.ps1 --fresh-start      (first run only)
#>
param([Parameter(ValueFromRemainingArguments = $true)] $ExtraArgs)

$ErrorActionPreference = 'Continue'

$ScriptDir  = $PSScriptRoot
$RepoDir    = Split-Path $ScriptDir -Parent
$ProjectDir = Split-Path $RepoDir -Parent
$Venv       = Join-Path $env:LOCALAPPDATA 'options-wheel\.venv'
$RunStrat   = Join-Path $Venv 'Scripts\run-strategy.exe'
$LogDir     = Join-Path $RepoDir 'logs'
$EnvFile    = Join-Path $RepoDir '.env'
$AlertMd    = Join-Path $ProjectDir 'WHEEL ALERTS.md'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$RunLog    = Join-Path $LogDir "wheel_$Stamp.log"
$StatusLog = Join-Path $LogDir 'wheel_status.log'

function Write-Log($msg) {
  $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Add-Content -LiteralPath $RunLog -Value "[$ts] $msg"
}

function Notify-Failure($reason) {
  $human = Get-Date -Format 'yyyy-MM-dd HH:mm K'
  if (-not (Test-Path -LiteralPath $AlertMd)) {
    Set-Content -LiteralPath $AlertMd -Encoding UTF8 -Value "# WARNING - Wheel Alerts`r`n`r`nAuto-appended by ``run_wheel.ps1`` when a scheduled run fails. Clear entries once reviewed.`r`n"
  }
  Add-Content -LiteralPath $AlertMd -Encoding UTF8 -Value "- **$human** - wheel run FAILED ($reason). Run log: ``$RunLog``"
  try {
    $AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    $t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $x = $t.GetElementsByTagName('text')
    $x.Item(0).AppendChild($t.CreateTextNode('Options-Wheel run FAILED')) | Out-Null
    $x.Item(1).AppendChild($t.CreateTextNode("$reason - check wheel_status.log")) | Out-Null
    $n = [Windows.UI.Notifications.ToastNotification]::new($t)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($n)
  } catch { }
}

Write-Log "=== wheel run start (args: $ExtraArgs) ==="

# --- Load credentials from .env ---
if (-not (Test-Path -LiteralPath $EnvFile)) {
  Write-Log "ERROR: .env not found at $EnvFile"
  Add-Content -LiteralPath $StatusLog -Value "$Stamp FAILED no-env"
  Notify-Failure 'no .env file'
  exit 1
}
$envmap = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile) {
  if ($line -match '^\s*#') { continue }
  if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') { $envmap[$matches[1]] = $matches[2].Trim() }
}
$key    = $envmap['ALPACA_API_KEY']
$secret = $envmap['ALPACA_SECRET_KEY']
$isPaper = if ($envmap.ContainsKey('IS_PAPER')) { $envmap['IS_PAPER'].ToLower() -eq 'true' } else { $true }
$apiBase = if ($isPaper) { 'https://paper-api.alpaca.markets' } else { 'https://api.alpaca.markets' }

# Pass creds to the child process via environment (matches the WSL wrapper).
$env:ALPACA_API_KEY    = $key
$env:ALPACA_SECRET_KEY = $secret
$env:IS_PAPER          = $envmap['IS_PAPER']

# --- Pre-flight: cancel all open orders ---
Write-Log "Pre-flight: cancelling any open orders on $apiBase ..."
try {
  $headers = @{ 'APCA-API-KEY-ID' = $key; 'APCA-API-SECRET-KEY' = $secret }
  Invoke-RestMethod -Method Delete -Uri "$apiBase/v2/orders" -Headers $headers -TimeoutSec 30 | Out-Null
  Write-Log "Pre-flight cancel OK"
} catch {
  Write-Log "Pre-flight cancel error (non-fatal): $($_.Exception.Message)"
}

# --- Run the strategy ---
# Pipe through Add-Content (ANSI) rather than the `*>>` redirect, which in
# Windows PowerShell 5.1 writes UTF-16 and null-interleaves the log text.
Write-Log "Running run-strategy ..."
& $RunStrat --strat-log --log-level INFO @ExtraArgs 2>&1 | ForEach-Object { Add-Content -LiteralPath $RunLog -Value "$_" }
$rc = $LASTEXITCODE
Write-Log "run-strategy exited with code $rc"

if ($rc -eq 0) {
  Add-Content -LiteralPath $StatusLog -Value "$Stamp OK"
} else {
  Add-Content -LiteralPath $StatusLog -Value "$Stamp FAILED rc=$rc (see $RunLog)"
  Notify-Failure "rc=$rc"
}
Write-Log "=== wheel run end (rc=$rc) ==="
exit $rc
