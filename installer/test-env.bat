@echo off
rem  Test environment with several companies on this PC (C:\HRTest, its own MySQL; never touches C:\HRSystem). See test-env.ps1.
rem  test-env.bat add regina rogest-network/HRSystem-ReginaCenter test
rem  test-env.bat add template rogest-network/HRSystem-Template stable
rem  test-env.bat add test local        (the code in Source/ on this PC, before anything is published)
rem  test-env.bat seed <name|all>   (520+ invented employees and records)
rem  test-env.bat panel   (opens http://localhost:3600 : pick the company to enter)
rem  test-env.bat list | update <name|all> | start [name|all] | stop [name|all] | remove <name>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-env.ps1" %*
exit /b %ERRORLEVEL%
