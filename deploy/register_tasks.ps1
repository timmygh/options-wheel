<#
  register_tasks.ps1 - register the options-wheel schedule in Windows Task Scheduler.

  Replaces the old WSL cron. Task Scheduler is the right host because it:
    - survives reboots,
    - can WAKE the machine from sleep to run (WakeToRun), and
    - catches up a missed run when the machine was off/asleep (StartWhenAvailable).

  Times are LOCAL (this box is Asia/Hong_Kong, no DST). ET->HKT assumes EDT
  (UTC-4); HKT is UTC+8, so US market 10:00/13:00/15:30 ET map to HKT below.
  RE-CHECK these at the US DST switches (Mar / Nov).

    Wheel  22:00  Mon-Fri   = 10:00 ET (same day)
    Wheel  01:00  Tue-Sat   = 13:00 ET (previous day)
    Wheel  03:30  Tue-Sat   = 15:30 ET (previous day)
    Report 04:15  Tue-Sat   = 16:15 ET (post-close)

  Tasks run as the current user, "only when logged on" (locked is fine; wake
  works while the session exists). Re-run this script any time to recreate them
  (it uses -Force). Run it as the user who will be logged in - no admin needed.
#>
$ErrorActionPreference = 'Stop'

$Deploy   = $PSScriptRoot
$PSExe    = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$WheelPs1 = Join-Path $Deploy 'run_wheel.ps1'
$RptPs1   = Join-Path $Deploy 'run_report.ps1'
$TaskPath = '\OptionsWheel\'
$User     = "$env:USERDOMAIN\$env:USERNAME"

$settings = New-ScheduledTaskSettingsSet `
  -WakeToRun `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 1)

$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited

function Register-Wheel($name, $script, $time, [string[]]$days, $extra) {
  $argline = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
  if ($extra) { $argline += " $extra" }
  $action  = New-ScheduledTaskAction -Execute $PSExe -Argument $argline
  $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $time
  Register-ScheduledTask -TaskName $name -TaskPath $TaskPath `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
  Write-Host "registered: $TaskPath$name  @ $time  [$($days -join ',')]"
}

$mf  = 'Monday','Tuesday','Wednesday','Thursday','Friday'
$tsa = 'Tuesday','Wednesday','Thursday','Friday','Saturday'

Register-Wheel 'Wheel-1000ET' $WheelPs1 '22:00' $mf  $null
Register-Wheel 'Wheel-1300ET' $WheelPs1 '01:00' $tsa $null
Register-Wheel 'Wheel-1530ET' $WheelPs1 '03:30' $tsa $null
Register-Wheel 'Report-1615ET' $RptPs1  '04:15' $tsa $null

Write-Host ""
Write-Host "=== registered tasks under $TaskPath ==="
Get-ScheduledTask -TaskPath $TaskPath | Select-Object TaskName, State |
  Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Next run times:"
Get-ScheduledTask -TaskPath $TaskPath | ForEach-Object {
  $info = $_ | Get-ScheduledTaskInfo
  Write-Host ("  {0,-16} -> {1}" -f $_.TaskName, $info.NextRunTime)
}
