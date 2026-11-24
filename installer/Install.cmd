@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >NUL 2>&1
if errorlevel 1 (
  echo Windows PowerShell not found.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Gui %*
if errorlevel 1 (
  echo.
  echo Installation failed. See the log above or %%TEMP%%\RaceNetLocal-install.log
  pause
)
exit /b 0
