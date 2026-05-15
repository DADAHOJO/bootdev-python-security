@echo off
set SCRIPT_PATH=%~dp0run-daily-sync.ps1
if not exist "%SCRIPT_PATH%" (
  echo Run script not found: %SCRIPT_PATH%
  exit /b 1
)
powershell -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
