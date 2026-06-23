<#
  run_report.ps1 - Windows-native wrapper for wheel_report.py.
  PowerShell port of deploy/run_report.sh. Writes a dated Markdown report into
  <project>\reports\. Paths derived from this script's location (repo-portable).
  The venv lives at %LOCALAPPDATA%\options-wheel\.venv (outside the synced vault).
#>
$ErrorActionPreference = 'Continue'

$ScriptDir = $PSScriptRoot
$RepoDir   = Split-Path $ScriptDir -Parent
$Venv      = Join-Path $env:LOCALAPPDATA 'options-wheel\.venv'
$Py        = Join-Path $Venv 'Scripts\python.exe'
$LogDir    = Join-Path $RepoDir 'logs'
$Log       = Join-Path $LogDir 'report.log'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Add-Content -LiteralPath $Log -Value "[$ts] running wheel_report.py"

# Pipe through Add-Content (ANSI); the `*>>` redirect writes UTF-16 in PS 5.1.
& $Py (Join-Path $ScriptDir 'wheel_report.py') 2>&1 | ForEach-Object { Add-Content -LiteralPath $Log -Value "$_" }
$rc = $LASTEXITCODE

$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Add-Content -LiteralPath $Log -Value "[$ts] report rc=$rc"
exit $rc
