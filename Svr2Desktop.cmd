@echo off
rem ===========================================================================
rem  Svr2Desktop launcher -- double-click entry point for the PowerShell script
rem
rem  TUNING ONLY. For the full "prepare this server as a desktop" flow -- tuning
rem  followed by a software deployment from the BobSoft payload -- use
rem  BobWinSvrTurn.cmd instead. Keep the two launchers in step: the host choice,
rem  the elevation probe and the pause rule are deliberately identical in both.
remrem  This is a thin wrapper and does exactly four things:
rem    1) finds the .ps1 named after THIS file (rename the pair together and it
rem       keeps working -- no hard-coded script name anywhere)
rem    2) prefers pwsh.exe (PowerShell 7 -> the script enhanced mode) and falls
rem       back to powershell.exe (5.1, built into every Server 2016-2025)
rem    3) requests elevation ONCE -- never in a loop
rem    4) keeps the window open only for a double-click (which never carries
rem       arguments), so an unattended run such as
rem           Svr2Desktop.cmd -Stage All -Json -Force -ExitOnFail
rem       never hangs on "Press any key".
rem
rem  Exit codes are propagated: 0 = no failure, 2 = FAIL / CHECK-ERROR
rem  (-ExitOnFail), 1 = fatal error. See the script header for full usage.
rem ===========================================================================

setlocal EnableExtensions
set "SCRIPT=%~dp0%~n0.ps1"
set "ARGS=%*"

if not exist "%SCRIPT%" (
    echo [ERROR] %~n0.ps1 was not found next to this launcher.
    echo         Expected: %SCRIPT%
    echo.
    pause
    exit /b 1
)

rem --- pick the best available host ---
set "PSEXE=powershell.exe"
set "PSMODE=Windows PowerShell 5.1 (compatibility mode)"
where pwsh.exe >nul 2>&1
if not errorlevel 1 (
    set "PSEXE=pwsh.exe"
    set "PSMODE=PowerShell 7 (enhanced mode)"
)
where %PSEXE% >nul 2>&1
if errorlevel 1 (
    echo [ERROR] %PSEXE% was not found on this machine.
    echo         Windows PowerShell 5.1 ships with every Windows Server and is
    echo         required as the fallback host.
    echo.
    pause
    exit /b 1
)

rem --- elevation probe -------------------------------------------------------
rem  fltmc fails for a non-elevated caller and does NOT depend on any service.
rem  (The old "net session" probe went wrong whenever the Server service was
rem   stopped: an already-elevated session looked unelevated, and the script
rem   re-launched itself over and over with no visible UAC prompt.)
fltmc >nul 2>&1
if not errorlevel 1 goto :launch

if defined SVR2D_RUNAS (
    echo [ERROR] still not elevated after requesting UAC. Start this from an
    echo         elevated PowerShell window instead. Nothing was changed.
    echo.
    pause
    exit /b 1
)

echo Administrator privileges are required - requesting elevation...
rem  The marker makes the elevated copy able to tell that it already asked.
rem  Start-Process inherits this environment block, so the marker travels.
set "SVR2D_RUNAS=1"
rem  Branch with goto rather than an if-block: a ")" inside %ARGS% would break
rem  a parenthesised block at parse time (cmd expands it before running it).
if not "%ARGS%"=="" goto :relaunch_with_args
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:relaunch_with_args
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ARGS%' -Verb RunAs"
exit /b

:launch
echo Host: %PSMODE%
echo.
%PSEXE% -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo Script exited with code %RC%.

rem --- keep the window open for a double-click only ---------------------------
rem  A double-click never carries arguments; anything unattended does.
rem  The two cases are disjoint by construction, so no pause is ever reached
rem  by a scheduled task or an automation wrapper.
if not "%ARGS%"=="" goto :done
echo %cmdcmdline% | find /i "%~nx0" >nul
if not errorlevel 1 pause
:done
exit /b %RC%
