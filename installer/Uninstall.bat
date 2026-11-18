@echo off
setlocal
cd /d "%~dp0"
title HRSystem Uninstall
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Po kerkohet Administrator...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "SCRIPT=%~dp0files\uninstall.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0uninstall.ps1"
set "WIZARD=%~dp0files\uninstall-wizard.ps1"
if not exist "%WIZARD%" set "WIZARD=%~dp0uninstall-wizard.ps1"
rem hr-links.ps1 closes the folders and removes links before anything is deleted; uninstall.ps1 loads it from its own folder (TEMP).
set "LINKS=%~dp0files\hr-links.ps1"
if not exist "%LINKS%" set "LINKS=%~dp0hr-links.ps1"
rem Run from copies in TEMP and leave this folder: a folder that is the working folder of a window cannot be deleted.
copy /y "%SCRIPT%" "%TEMP%\hrsystem-uninstall.ps1" >nul
if exist "%LINKS%" copy /y "%LINKS%" "%TEMP%\hr-links.ps1" >nul
rem The installation folder is this one when it holds current.txt (otherwise the window finds it from the Windows task).
if exist "%~dp0current.txt" set "HRSYSTEM_ROOT=%~dp0"
if defined HRSYSTEM_ROOT if "%HRSYSTEM_ROOT:~-1%"=="\" set "HRSYSTEM_ROOT=%HRSYSTEM_ROOT:~0,-1%"
rem The window (Keep: Database Po / Jo, then Next). "Uninstall.bat /console" runs the console version instead.
if exist "%WIZARD%" if /i not "%~1"=="/console" (
  copy /y "%WIZARD%" "%TEMP%\hrsystem-uninstall-wizard.ps1" >nul
  cd /d "%TEMP%"
  start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%TEMP%\hrsystem-uninstall-wizard.ps1" -Engine "%TEMP%\hrsystem-uninstall.ps1"
  exit /b 0
)
cd /d "%TEMP%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\hrsystem-uninstall.ps1"
set "EC=%ERRORLEVEL%"
echo.
pause
exit /b %EC%
