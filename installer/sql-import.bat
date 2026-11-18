@echo off
setlocal
cd /d "%~dp0"
title HRSystem SQL Import
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
rem  sql-import.bat                 -> hap dritaren per te zgjedhur skedarin .sql
rem  sql-import.bat skedari.sql     -> ekzekuton ate skedar
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sql-import.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
  echo Perfundoi me sukses.
) else (
  echo Perfundoi me GABIM. Kodi: %EC%  ^(detajet: Sql-Import.log^)
)
pause
exit /b %EC%
