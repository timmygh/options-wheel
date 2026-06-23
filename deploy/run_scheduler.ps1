<#
  run_scheduler.ps1 - foreground "manual" scheduler for the options-wheel bot.

  You start this yourself (start_wheel_scheduler.bat, or run it directly) and
  leave the window open. While it runs it follows the trading schedule and fires
  the existing wrappers at the right times. Stop it with Ctrl+C or by closing the
  window - nothing runs once it's stopped. This REPLACES Windows Task Scheduler.

  Times are LOCAL (this box is Asia/Hong_Kong, no DST). ET->HKT assumes EDT
  (UTC-4); RE-CHECK at the US DST switches (Mar / Nov).
    Wheel  22:00  Mon-Fri  = 10:00 ET (same day)
    Wheel  01:00  Tue-Sat  = 13:00 ET (previous day)
    Wheel  03:30  Tue-Sat  = 15:30 ET (previous day)
    Report 04:15  Tue-Sat  = 16:15 ET (post-close)

  Notes:
  - It only fires slots that occur WHILE it is running; it does not back-fill a
    slot that already passed before you started it. (Run a wrapper by hand if you
    want an immediate one-off run.)
  - Keep the machine awake while this runs. It polls every 30s with a 5-min grace
    window, so a brief sleep is tolerated, but a long sleep can miss a slot.
  - Each run is launched as its own powershell process, so a failure in one run
    never kills the scheduler.

  Usage:
    run_scheduler.ps1                 # start the loop
    run_scheduler.ps1 -ShowSchedule   # just print the next fire times and exit
#>
param([switch]$ShowSchedule)

$ErrorActionPreference = 'Continue'

$Deploy   = $PSScriptRoot
$RepoDir  = Split-Path $Deploy -Parent
$PSExe    = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$LogDir   = Join-Path $RepoDir 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$SchedLog = Join-Path $LogDir 'scheduler.log'

$WheelPs1 = Join-Path $Deploy 'run_wheel.ps1'
$RptPs1   = Join-Path $Deploy 'run_report.ps1'

$mf  = 'Monday','Tuesday','Wednesday','Thursday','Friday'
$tsa = 'Tuesday','Wednesday','Thursday','Friday','Saturday'

$jobs = @(
  [pscustomobject]@{ Name = 'Wheel-1000ET';  Time = '22:00'; Days = $mf;  Script = $WheelPs1 }
  [pscustomobject]@{ Name = 'Wheel-1300ET';  Time = '01:00'; Days = $tsa; Script = $WheelPs1 }
  [pscustomobject]@{ Name = 'Wheel-1530ET';  Time = '03:30'; Days = $tsa; Script = $WheelPs1 }
  [pscustomobject]@{ Name = 'Report-1615ET'; Time = '04:15'; Days = $tsa; Script = $RptPs1   }
)

function Get-NextOccurrence($timeStr, $days, $from) {
  $p = $timeStr.Split(':'); $h = [int]$p[0]; $m = [int]$p[1]
  for ($i = 0; $i -lt 8; $i++) {
    $d = $from.Date.AddDays($i)
    if ($days -contains $d.DayOfWeek.ToString()) {
      $cand = $d.AddHours($h).AddMinutes($m)
      if ($cand -gt $from) { return $cand }
    }
  }
  return $null
}

function Write-Sched($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  Add-Content -LiteralPath $SchedLog -Value $line
}

$now = Get-Date
Write-Host ""
Write-Host "  Options-Wheel manual scheduler   (all times LOCAL / HKT)"
Write-Host "  ------------------------------------------------------"
foreach ($j in $jobs) {
  $n = Get-NextOccurrence $j.Time $j.Days $now
  Write-Host ("  next  {0,-15} {1:ddd yyyy-MM-dd HH:mm}" -f $j.Name, $n)
}
Write-Host ""

if ($ShowSchedule) { return }

Write-Sched "=== scheduler started (PID $PID) - leave this window open; Ctrl+C or close it to stop ==="
$fired = @{}
$grace = 300   # seconds: fire if we are within 5 min of the slot and haven't yet
try {
  while ($true) {
    $now = Get-Date
    foreach ($j in $jobs) {
      if ($j.Days -contains $now.DayOfWeek.ToString()) {
        $p = $j.Time.Split(':')
        $sched = $now.Date.AddHours([int]$p[0]).AddMinutes([int]$p[1])
        $delta = ($now - $sched).TotalSeconds
        $key = "{0}|{1}" -f $j.Name, $now.ToString('yyyy-MM-dd')
        if ($delta -ge 0 -and $delta -lt $grace -and -not $fired[$key]) {
          $fired[$key] = $true
          Write-Sched ("FIRING {0} -> {1}" -f $j.Name, (Split-Path $j.Script -Leaf))
          & $PSExe -NoProfile -ExecutionPolicy Bypass -File $j.Script
          Write-Sched ("DONE   {0} rc={1}" -f $j.Name, $LASTEXITCODE)
        }
      }
    }
    Start-Sleep -Seconds 30
  }
}
finally {
  Write-Sched "=== scheduler stopped ==="
}
