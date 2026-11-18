@echo off
rem HRS-Setup.zip: opens the newest HRSystem Setup (downloaded from the private repo HRSystem-Setup). Double-click this file.
cd /d "%~dp0"
set "BS=%~dp0files\bootstrap.ps1"
if not exist "%BS%" (
  echo files\bootstrap.ps1 nuk u gjet. Nxirre tere zip-in para se ta hapesh.
  pause
  exit /b 1
)
start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%BS%"
exit /b 0
