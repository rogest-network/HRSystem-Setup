@echo off
setlocal
cd /d "%~dp0"
title HRSystem Update
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Po kerkohet Administrator...
  if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  ) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
  )
  exit /b
)
rem  update.bat            -> merr versionin e fundit nga GitHub dhe e instalon
rem  update.bat check      -> vetem tregon nese ka version te ri
rem  update.bat skedari.zip -> instalon nje zip lokal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
  echo Perfundoi me sukses.
) else (
  echo Perfundoi me GABIM. Kodi: %EC%  ^(detajet: Updater.log^)
)
pause
exit /b %EC%
