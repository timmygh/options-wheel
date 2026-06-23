<#
  unregister_tasks.ps1 - remove the auto Windows Task Scheduler jobs.

  We switched to the manual foreground scheduler (run_scheduler.ps1), so the
  background \OptionsWheel\ tasks should not exist (they would double-fire).
  Run register_tasks.ps1 again if you ever want to go back to background auto-runs.
#>
$ErrorActionPreference = 'SilentlyContinue'
$tasks = Get-ScheduledTask -TaskPath '\OptionsWheel\' -ErrorAction SilentlyContinue
if ($tasks) {
  $tasks | Unregister-ScheduledTask -Confirm:$false
  Write-Host "Removed $($tasks.Count) task(s) under \OptionsWheel\:"
  $tasks | ForEach-Object { Write-Host "  - $($_.TaskName)" }
} else {
  Write-Host "No tasks found under \OptionsWheel\ (already clean)."
}
# Best-effort: remove the now-empty task folder.
try {
  $svc = New-Object -ComObject 'Schedule.Service'
  $svc.Connect()
  $root = $svc.GetFolder('\')
  $root.DeleteFolder('OptionsWheel', 0)
  Write-Host "Removed empty task folder \OptionsWheel\"
} catch { }
