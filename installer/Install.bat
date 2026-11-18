@echo off
setlocal
cd /d "%~dp0"
title HRSystem Install
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Po kerkohet Administrator...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "SCRIPT=%~dp0files\installer.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0installer.ps1"
set "WIZARD=%~dp0files\wizard.ps1"
if not exist "%WIZARD%" set "WIZARD=%~dp0wizard.ps1"
rem The setup window (Next, Next): disk and folder, database name, tokens. "Install.bat /console" runs the old console setup instead.
if exist "%WIZARD%" if /i not "%~1"=="/console" (
  cd /d "%SystemRoot%"
  start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%WIZARD%"
  exit /b 0
)
rem Leave the extracted folder (a folder that is a window's working folder cannot be deleted afterwards).
cd /d "%SystemRoot%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
  echo Instalimi perfundoi me sukses. Dashboard-i hapet te http://127.0.0.1:3500
) else (
  echo Instalimi perfundoi me gabim. Kodi: %EC%
)
pause
exit /b %EC%
