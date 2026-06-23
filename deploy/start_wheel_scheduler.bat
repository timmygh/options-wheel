@echo off
REM Double-click to start the options-wheel manual scheduler.
REM Leave this window OPEN while you want the bot to trade on schedule.
REM Stop it by pressing Ctrl+C or just closing this window.
title Options-Wheel Scheduler
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_scheduler.ps1"
echo.
echo Scheduler exited. Press any key to close this window.
pause >nul
