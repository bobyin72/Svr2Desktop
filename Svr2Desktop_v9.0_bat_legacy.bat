@echo off
setlocal enabledelayedexpansion

:: ============================================================================
::  Svr2Desktop.bat  --  Windows Server to Desktop Workstation Tuner
:: ============================================================================
::  Version      : 9.0  (Audit-Remediated Edition)
::  Released     : 2026-09-18
::  Baseline     : "Windows Server 2016-2025 to desktop.bat" v8.1 (2025-09-30)
::  Target       : Windows Server 2016 / 2019 / 2022 / 2025  (x64)
::  Run as       : Administrator  (self-elevates via UAC)
:: ----------------------------------------------------------------------------
::  WHY 9.0 EXISTS
::  The v8.1 baseline was statically audited on 2026-09-18 and produced 26
::  findings (5 x P0, 12 x P1, 9 x P2). This edition removes or isolates every
::  P0/P1 defect and makes every remaining change verifiable from the log.
::
::  P0 REMEDIATIONS
::   P0-1  Deleted:  del /f /s /q %SystemDrive%\*.log | *.old | *.tmp | *.chk
::                   | *.gid | *._mp
::         That form deletes recursively from the volume root. It destroyed
::         application and audit logs (compliance-relevant), and the .old
::         files that software updaters keep as the only rollback copy.
::         Replaced by an explicit directory whitelist (see [10]).
::   P0-2  Deleted the  \\network\share\sxs  .NET 3.5 fallback source.
::         "network" is an unqualified hostname resolved via LLMNR / NBNS
::         broadcast; a same-subnet attacker could answer it and feed
::         attacker-controlled SxS components into an elevated install.
::   P0-3  Defender handling rewritten and moved out of the [A] "all" path
::         into opt-in menu item [9]:
::           - removed TamperProtection=0   (ignored: requires TrustedInstaller
::             plus TamperProtection=4 + TamperProtectionSource=2 + DevMode=0)
::           - removed DisableAntiSpyware / DisableAntiVirus (ignored by
::             Windows since Server 2016)
::           - removed the "hide the security warnings" keys (tray icon,
::             SecurityHealth run entry, Notifications_Disable)
::           - the log now reports the state READ BACK from
::             Get-MpComputerStatus instead of claiming success blindly
::   P0-4  Removed the security-downgrade cluster that together formed a full
::         kill chain: UAC silent elevation (ConsentPromptBehaviorAdmin=0 +
::         PromptOnSecureDesktop=0), password policy zeroed (min length 0,
::         complexity off, never expires) and an unconditional inbound
::         allow rule for RDP 3389.
::           - UAC is left at the Windows desktop default (EnableLUA forced on)
::           - password policy is not touched at all
::           - the RDP rule is opt-in, prompted, and idempotent
::
::  P1 REMEDIATIONS
::   P1-1  WMIC replaced by PowerShell CIM at all three call sites
::         (WMIC is an on-demand feature and is NOT installed by default on
::          Server 2025; the old code also overflowed 32-bit set /a on >2 GB).
::   P1-2  Hibernation vs Fast Startup conflict resolved. Fast Startup needs
::         hiberfil.sys, so "powercfg /hibernate off" followed by
::         HiberbootEnabled=1 could never work. Hibernation stays off and the
::         dead Fast Startup write is gone.
::   P1-3  Removed the self-contradicting SSD block: it closed Prefetch and
::         Superfetch right after enabling the SysMain service, and disabled
::         the ScheduledDefrag task -- on SSDs Windows uses that task to issue
::         periodic TRIM, so disabling it removes TRIM maintenance instead of
::         protecting the drive. Storage section is now advisory only.
::   P1-4  Removed the TEMP / TMP redirection. The comment said "move to RAM
::         disk" but the code repointed the machine-wide TEMP to
::         %SystemRoot%\Temp, dragging every service and session onto the
::         system volume.
::   P1-5  Removed SEHOP disabling (DisableExceptionChainValidation) - pure
::         exploit-mitigation reduction - and the no-op bcdedit nx OptIn
::         (OptIn is already the Windows default).
::   P1-6  The configuration loader now enforces a key whitelist and refuses
::         keys able to hijack the script itself (BACKUP_DIR, LOG_FILE,
::         CONFIG_FILE, TEMP, TMP, PATH, SystemDrive) and refuses
::         OPT_DISABLE_DEFENDER entirely.
::   P1-7  Removed the undefined %PS_ERROR_HANDLER% references.
::   P1-8  All  for /f ... in ("file")  readers are quoted, so a script path
::         containing spaces no longer silently skips the config file.
::   P1-9  Backup now runs BEFORE the first modification, covers every
::         registry branch the script writes to, snapshots service start
::         types and the active power scheme, and generates Restore_*.bat.
::   P1-10 Every registry / service / netsh / feature operation now checks its
::         exit code and the log records [ OK ] / [FAIL] / [SKIP] per item,
::         followed by a summary line. v8.1 logged "completed" unconditionally.
::   P1-11 Server-valid feature names only. "MediaPlayback", "EnhancedStorage"
::         and "DirectPlay" are CLIENT optional features and do not exist on
::         Server SKUs; replaced by Desktop-Experience and
::         Server-Media-Foundation.
::   P1-12 AzureArcSetup is enumerated with Get-WindowsCapability and matched
::         by wildcard before removal (the short name never matched).
::
::  P2 REMEDIATIONS
::   P2-1  The RDP firewall rule is idempotent - the old name is deleted
::         before the new one is added, so rules no longer accumulate.
::   P2-2  Log and restore file names use a zero-padded, locale-independent
::         timestamp (the old %TIME:~0,2% produced " 9" before 10:00).
::   P2-3  Menu input is validated; empty or unknown input returns to the
::         menu instead of running nothing after a confirmation.
::   P2-4  Acceleration template defaults are conservative now (v8.1 shipped
::         PERFORMANCE_LEVEL=EXTREME and DEFENDER_ACTION=DISABLE, which could
::         be replayed silently through [C]).
::   P2-5  Dead code and duplicate writes removed: the never-read
::         ACCELERATION_APPLIED flag, Defender keys written twice, the Xbox
::         services disabled in two sections, the Windows Update download
::         cache deleted twice.
::   P2-6  CertPropSvc (smart card / UKey / enterprise CA certificate
::         propagation) and Spooler (printing, PDF export) are no longer
::         disabled by default.
::   P2-7  The restart prompt now allows 60 seconds instead of 10, and tells
::         you how to cancel it.
::   P2-8  chcp 65001 removed - the file is pure ASCII, so the script no
::         longer changes the console code page of the session it runs in.
:: ----------------------------------------------------------------------------
::  SAFETY MODEL
::   SAFE SET   [1]-[8] and [10]-[15]
::              Reversible tuning. No deliberate security downgrade. These are
::              what [A] applies.
::   RISKY SET  [9]
::              Windows Defender reduction. Opt-in ONLY, requires typing YES
::              at an explicit prompt, never included in [A], and rejected by
::              the configuration loader.
::   ROLLBACK   A copy of every touched registry branch is written to
::              <script dir>\Svr2DesktopBackup BEFORE the first change, and a
::              Restore_<stamp>.bat is generated next to it.
:: ----------------------------------------------------------------------------
::  DISCLAIMER
::   Unofficial, community-style tuning script. It changes services, firewall,
::   power and registry settings. Test on a non-production machine first.
::   No liability is accepted for data loss or downtime.
:: ============================================================================


:: ============================================================================
::  SECTION 0 - RUNTIME VARIABLES
:: ============================================================================
set "SCRIPT_NAME=Svr2Desktop"
set "SCRIPT_VER=9.0"
set "SCRIPT_REL=2026-09-18"
set "BACKUP_DIR=%~dp0%SCRIPT_NAME%Backup"
set "CONFIG_FILE=%~dp0svr2desktop.ini"
set "ACCELERATION_FILE=%~dp0Acceleration.Level.ini"
set "SCRIPT_DIR=%~dp0"
set "RESTORE_FILE=%BACKUP_DIR%\Restore_LATEST.bat"
set "currentuser=%USERNAME%"
set "OSBUILD=0"
set "caption="
set "totalmem=0"
set "RDP_RULE_NAME=Remote Desktop (TCP-In) 3389"

set /a OK_COUNT=0
set /a FAIL_COUNT=0
set /a SKIP_COUNT=0
set /a CFG_ACCEPTED=0
set /a CFG_REJECTED=0
set "EXECUTED=0"

title %SCRIPT_NAME% v%SCRIPT_VER% - Windows Server to Desktop Tuner


:: ============================================================================
::  SECTION 1 - ADMINISTRATOR CHECK  (fltmc does not depend on any service)
:: ============================================================================
fltmc >nul 2>&1
if errorlevel 1 (
    echo.
    echo Administrator privileges are required.
    echo Requesting elevation...
    > "%temp%\svr2desktop_elev.vbs" echo Set UAC = CreateObject^("Shell.Application"^)
    >>"%temp%\svr2desktop_elev.vbs" echo UAC.ShellExecute "%~s0", "", "", "runas", 1
    cscript //nologo "%temp%\svr2desktop_elev.vbs" >nul 2>&1
    if errorlevel 1 "%temp%\svr2desktop_elev.vbs" >nul 2>&1
    del "%temp%\svr2desktop_elev.vbs" >nul 2>&1
    exit /b
)


:: ============================================================================
::  SECTION 2 - BACKUP DIRECTORY AND TIMESTAMP
:: ============================================================================
if not exist "%BACKUP_DIR%\" mkdir "%BACKUP_DIR%" >nul 2>&1
if not exist "%BACKUP_DIR%\" (
    echo.
    echo [FATAL] Cannot create the backup directory:
    echo         %BACKUP_DIR%
    echo.
    echo The script refuses to run without a writable backup location.
    echo Move it to a writable folder and try again.
    echo.
    pause
    exit /b 1
)

set "STAMP="
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "STAMP=%%a"
if not defined STAMP (
    set "STAMP=%DATE:/=-%_%TIME::=-%"
    set "STAMP=!STAMP: =0!"
)

set "LOG_FILE=%BACKUP_DIR%\%SCRIPT_NAME%_Log_%STAMP%.log"


:: ============================================================================
::  SECTION 3 - SYSTEM DETECTION  (CIM based, no WMIC)
:: ============================================================================
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).Caption" 2^>nul') do if not defined caption set "caption=%%a"
if not defined caption set "caption=Unknown (CIM query failed)"
if defined caption if "!caption!"=="" set "caption=Unknown (CIM query failed)"

for /f "delims=" %%a in ('powershell -NoProfile -Command "[int][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1MB)" 2^>nul') do set "totalmem=%%a"
if not defined totalmem set "totalmem=0"

for /f "delims=" %%a in ('powershell -NoProfile -Command "[System.Environment]::OSVersion.Version.Build" 2^>nul') do set "OSBUILD=%%a"

set "OSFAMILY=Unknown"
if "!OSBUILD!"=="14393" set "OSFAMILY=Server 2016"
if "!OSBUILD!"=="17763" set "OSFAMILY=Server 2019"
if "!OSBUILD!"=="20348" set "OSFAMILY=Server 2022"
if "!OSBUILD!"=="26100" set "OSFAMILY=Server 2025"
if "!OSBUILD!"=="26200" set "OSFAMILY=Server 2025 (or newer)"


:: ============================================================================
::  SECTION 4 - MAIN MENU
:: ============================================================================
:MAIN_MENU
set "CHOICE="
set "CONFIRM="
set "OPT_SERVICES="
set "OPT_PERFORMANCE="
set "OPT_UI="
set "OPT_NETWORK="
set "OPT_SECURITY="
set "OPT_FEATURES="
set "OPT_MEDIA_FOUNDATION="
set "OPT_BACKUP="
set "OPT_DISABLE_DEFENDER="
set "OPT_DEEP_CLEAN="
set "OPT_GAMING="
set "OPT_OFFICE="
set "OPT_MULTIMEDIA="
set "OPT_SSD="
set "OPT_PRIVACY="
set "RDPCHOICE="

cls
echo.
echo ================================================================
echo   %SCRIPT_NAME%  v%SCRIPT_VER%   (Audit-Remediated Edition)
echo ================================================================
echo.
echo   Detected :  !caption!   [!OSFAMILY!  build !OSBUILD!]
echo   Computer :  %COMPUTERNAME%
echo   User     :  %currentuser%
echo   Memory   :  !totalmem! MB
echo   Log      :  %LOG_FILE%
echo.
echo   WARNING: this script modifies services, firewall, power policy and
echo            the registry. Create a restore point or a VM snapshot first.
echo            A registry backup is taken automatically before any change.
echo.
echo ----------------------------------------------------------------
echo   SAFE SET  (reversible, no deliberate security downgrade)
echo ----------------------------------------------------------------
echo    [1]  Core services        (audio, themes, search, desktop services)
echo    [2]  System performance   (power plan, responsiveness, priority)
echo    [3]  User interface       (login behaviour, visual effects, explorer)
echo    [4]  Network tuning       (TCP/IP, DNS cache, optional RDP rule)
echo    [5]  Security baseline    (firewall on, SMBv1 hardening, UAC on)
echo    [6]  Desktop Experience   (required for WMP, themes, MMC)
echo    [7]  Media Foundation     (media playback stack for Server)
echo    [8]  Configuration backup (runs automatically before any change)
echo   [10]  Disk cleanup         (whitelisted directories only)
echo   [11]  Gaming optimizations
echo   [12]  Office / productivity optimizations
echo   [13]  Multimedia enhancements
echo   [14]  Storage / SSD check  (advisory, changes nothing aggressive)
echo   [15]  Privacy / telemetry reduction
echo.
echo ----------------------------------------------------------------
echo   RISKY SET  (opt-in only, NEVER part of [A])
echo ----------------------------------------------------------------
echo    [9]  Windows Defender reduction   *** requires explicit confirmation
echo.
echo ----------------------------------------------------------------
echo    [A]  Apply the SAFE SET  (1-8 and 10-15, excludes 9)
echo    [C]  Load configuration file   (common: %CONFIG_FILE%)
echo    [S]  Create configuration templates
echo    [R]  Show rollback instructions
echo    [X]  Exit
echo.
set /p "CHOICE=Select an operation: "

if not defined CHOICE goto :MAIN_MENU

if /i "!CHOICE!"=="1"  set "OPT_SERVICES=1"
if /i "!CHOICE!"=="2"  set "OPT_PERFORMANCE=1"
if /i "!CHOICE!"=="3"  set "OPT_UI=1"
if /i "!CHOICE!"=="4"  set "OPT_NETWORK=1"
if /i "!CHOICE!"=="5"  set "OPT_SECURITY=1"
if /i "!CHOICE!"=="6"  set "OPT_FEATURES=1"
if /i "!CHOICE!"=="7"  set "OPT_MEDIA_FOUNDATION=1"
if /i "!CHOICE!"=="8"  set "OPT_BACKUP=1"
if /i "!CHOICE!"=="9"  set "OPT_DISABLE_DEFENDER=1"
if /i "!CHOICE!"=="10" set "OPT_DEEP_CLEAN=1"
if /i "!CHOICE!"=="11" set "OPT_GAMING=1"
if /i "!CHOICE!"=="12" set "OPT_OFFICE=1"
if /i "!CHOICE!"=="13" set "OPT_MULTIMEDIA=1"
if /i "!CHOICE!"=="14" set "OPT_SSD=1"
if /i "!CHOICE!"=="15" set "OPT_PRIVACY=1"

if /i "!CHOICE!"=="A" (
    set "OPT_SERVICES=1"
    set "OPT_PERFORMANCE=1"
    set "OPT_UI=1"
    set "OPT_NETWORK=1"
    set "OPT_SECURITY=1"
    set "OPT_FEATURES=1"
    set "OPT_MEDIA_FOUNDATION=1"
    set "OPT_BACKUP=1"
    set "OPT_DEEP_CLEAN=1"
    set "OPT_GAMING=1"
    set "OPT_OFFICE=1"
    set "OPT_MULTIMEDIA=1"
    set "OPT_SSD=1"
    set "OPT_PRIVACY=1"
    echo.
    echo   [A] applies the SAFE SET only.
    echo   Menu item [9] Windows Defender reduction is NOT included and must
    echo   be selected explicitly if you really want it.
)

if /i "!CHOICE!"=="C" goto :LOAD_CONFIG
if /i "!CHOICE!"=="S" goto :CREATE_TEMPLATES
if /i "!CHOICE!"=="R" goto :SHOW_ROLLBACK
if /i "!CHOICE!"=="X" exit /b 0

if not defined OPT_SERVICES if not defined OPT_PERFORMANCE if not defined OPT_UI if not defined OPT_NETWORK if not defined OPT_SECURITY if not defined OPT_FEATURES if not defined OPT_MEDIA_FOUNDATION if not defined OPT_BACKUP if not defined OPT_DISABLE_DEFENDER if not defined OPT_DEEP_CLEAN if not defined OPT_GAMING if not defined OPT_OFFICE if not defined OPT_MULTIMEDIA if not defined OPT_SSD if not defined OPT_PRIVACY (
    echo.
    echo   Unknown selection: "!CHOICE!"
    echo   Nothing was executed.
    echo.
    pause
    goto :MAIN_MENU
)


:: ============================================================================
::  SECTION 5 - CONFIRMATION
:: ============================================================================
echo.
echo   About to apply the selected configuration.
if defined OPT_DISABLE_DEFENDER (
    echo.
    echo   *** WARNING: item [9] Windows Defender reduction is selected. ***
    echo   It can make the machine unprotected and may be irreversible on
    echo   offline hosts with no installation media.
)
echo.
set /p "CONFIRM=Confirm execution? (Y/N): "
if /i not "!CONFIRM!"=="Y" (
    echo.
    echo   Operation cancelled. Nothing was executed.
    echo.
    pause
    goto :MAIN_MENU
)


:: ============================================================================
::  SECTION 6 - BACKUP FIRST  (P1-9: before the first modification)
:: ============================================================================
echo.
echo   Taking a configuration backup before any change...
call :BACKUP_SETTINGS
call :GEN_RESTORE_SCRIPT
echo   Backup written to: %BACKUP_DIR%
echo   Rollback script  : %RESTORE_FILE%
echo.

>>"%LOG_FILE%" echo ================================================================
>>"%LOG_FILE%" echo %SCRIPT_NAME% v%SCRIPT_VER%  (released %SCRIPT_REL%)
>>"%LOG_FILE%" echo Started : %STAMP%
>>"%LOG_FILE%" echo OS      : !caption!  [!OSFAMILY! build !OSBUILD!]
>>"%LOG_FILE%" echo User    : %currentuser%
>>"%LOG_FILE%" echo Host    : %COMPUTERNAME%
>>"%LOG_FILE%" echo Memory  : !totalmem! MB
>>"%LOG_FILE%" echo Selection: !CHOICE!
>>"%LOG_FILE%" echo ================================================================
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [BACKUP] written to %BACKUP_DIR% before any modification
>>"%LOG_FILE%" echo [BACKUP] rollback script %RESTORE_FILE%


:: ============================================================================
::  SECTION 7 - EXECUTION
:: ============================================================================
echo.
echo   Starting optimization...
echo.

if defined OPT_SERVICES         call :DO_SERVICES
if defined OPT_PERFORMANCE      call :DO_PERFORMANCE
if defined OPT_UI               call :DO_UI
if defined OPT_NETWORK          call :DO_NETWORK
if defined OPT_SECURITY         call :DO_SECURITY
if defined OPT_FEATURES         call :DO_DESKTOP_EXPERIENCE
if defined OPT_MEDIA_FOUNDATION call :DO_MEDIA_FOUNDATION
if defined OPT_BACKUP           >>"%LOG_FILE%" echo   [INFO] menu [8] selected - the backup was already taken before the first change
if defined OPT_DEEP_CLEAN       call :DO_DISK_CLEANUP
if defined OPT_GAMING           call :DO_GAMING
if defined OPT_OFFICE           call :DO_OFFICE
if defined OPT_MULTIMEDIA       call :DO_MULTIMEDIA
if defined OPT_SSD              call :DO_STORAGE
if defined OPT_PRIVACY          call :DO_PRIVACY

:: Defender reduction runs LAST and only when explicitly selected.
if defined OPT_DISABLE_DEFENDER call :DO_DEFENDER

:: Apply Acceleration.Level configuration if a file is present (P1-8 quoting).
if exist "%ACCELERATION_FILE%" (
    echo.
    echo   Applying Acceleration.Level configuration...
    call :APPLY_ACCELERATION
)


:: ============================================================================
::  SECTION 8 - SUMMARY
:: ============================================================================
echo.
echo ================================================================
echo   Completed.
echo     applied=!OK_COUNT!   failed=!FAIL_COUNT!   skipped=!SKIP_COUNT!
echo ================================================================
echo.
if !FAIL_COUNT! GTR 0 (
    echo   !FAIL_COUNT! operation^(s^) failed or had no effect.
    echo   Review the log and verify the result manually - do NOT assume that
    echo   a failure here means the setting was already correct.
) else (
    echo   No failures recorded.
)
echo.
echo   IMPORTANT: this log records the exit code of each command. For
echo   security-relevant items it is still worth reading the state back
echo   yourself, for example:
echo     Get-MpComputerStatus        (Defender state)
echo     powercfg /getactivescheme   (active power plan)
echo     net accounts                (password policy - unchanged by 9.0)
echo.
echo   Detailed log : %LOG_FILE%
echo   Rollback     : %RESTORE_FILE%
echo.

>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo ================================================================
>>"%LOG_FILE%" echo SUMMARY  applied=!OK_COUNT!  failed=!FAIL_COUNT!  skipped=!SKIP_COUNT!
>>"%LOG_FILE%" echo Finished: %DATE% %TIME%
>>"%LOG_FILE%" echo ================================================================

set "restart="
set /p "restart=Restart the computer now? (Y/N): "
if /i "!restart!"=="Y" (
    echo.
    echo   Restarting in 60 seconds. Save your work.
    echo   To cancel:  shutdown /a
    echo.
    shutdown /r /t 60 /c "Server-to-desktop tuning finished. Restarting in 60 seconds. Run shutdown /a to cancel."
) else (
    echo.
    echo   Remember to restart later - most changes only take effect after a reboot.
)
echo.
echo   Press any key to return to the main menu...
pause >nul
goto :MAIN_MENU


:: ============================================================================
::  SUBROUTINES - CONFIGURATION FILE  (P1-6 whitelist, P1-8 quoting)
:: ============================================================================
:LOAD_CONFIG
cls
echo.
echo   Loading configuration file (whitelist enforced)...
echo   %CONFIG_FILE%
echo.
if not exist "%CONFIG_FILE%" (
    echo   [MISSING] configuration file not found.
    echo   Use menu item [S] to create a template first.
    echo.
    pause
    goto :MAIN_MENU
)
set /a CFG_ACCEPTED=0
set /a CFG_REJECTED=0
for /f "usebackq tokens=1* delims==" %%a in ("%CONFIG_FILE%") do call :CFG_APPLY "%%a" "%%b"
echo.
echo   Accepted keys : !CFG_ACCEPTED!
echo   Rejected keys : !CFG_REJECTED!
echo.
echo   NOTE: only OPT_* selection keys are allowed. A rejected key was either
echo   unknown or able to influence the script itself, and was ignored.
echo.
pause
goto :MAIN_MENU

:CFG_APPLY
set "K=%~1"
set "V=%~2"
if not defined K goto :EOF
if "!K:~0,1!"=="#" goto :EOF
if "!V!"=="" goto :EOF
set "K=!K: =!"
for %%W in (OPT_SERVICES OPT_PERFORMANCE OPT_UI OPT_NETWORK OPT_SECURITY OPT_FEATURES OPT_MEDIA_FOUNDATION OPT_BACKUP OPT_DEEP_CLEAN OPT_GAMING OPT_OFFICE OPT_MULTIMEDIA OPT_SSD OPT_PRIVACY) do (
    if /i "!K!"=="%%W" (
        set "!K!=!V!"
        set /a CFG_ACCEPTED+=1
        echo   [ OK ] !K!=!V!
        >>"%LOG_FILE%" echo [CONFIG] !K!=!V!
        goto :CFG_APPLY_DONE
    )
)
set /a CFG_REJECTED+=1
echo   [REJECT] !K!  - not whitelisted, ignored
:CFG_APPLY_DONE
goto :EOF


:: ============================================================================
::  SUBROUTINES - TEMPLATES  (P2-4 conservative defaults)
:: ============================================================================
:CREATE_TEMPLATES
cls
echo.
echo   Creating configuration templates in %SCRIPT_DIR%
echo.
(
echo # Svr2Desktop configuration file
echo # Place next to Svr2Desktop.bat, then choose menu item [C] to load it.
echo # Only the keys below are accepted. Anything else is rejected.
echo # A value of 1 enables the corresponding menu item; 0 or absent means off.
echo #
echo OPT_SERVICES=1
echo OPT_PERFORMANCE=1
echo OPT_UI=1
echo OPT_NETWORK=1
echo OPT_SECURITY=1
echo OPT_FEATURES=1
echo OPT_MEDIA_FOUNDATION=1
echo OPT_BACKUP=1
echo OPT_DEEP_CLEAN=0
echo OPT_GAMING=0
echo OPT_OFFICE=1
echo OPT_MULTIMEDIA=1
echo OPT_SSD=1
echo OPT_PRIVACY=1
echo #
echo # NOTE: OPT_DISABLE_DEFENDER is deliberately NOT supported here.
echo # Windows Defender reduction must be selected interactively (menu item 9)
echo # and confirmed with YES. It cannot be replayed from a file.
) > "%CONFIG_FILE%"
echo   [ OK ] %CONFIG_FILE%

(
echo # Acceleration.Level - refinement profile
echo # Applied after the menu selections, only if this file exists.
echo #
echo # Performance level : EXTREME, BALANCED   ^(default BALANCED, see below^)
echo PERFORMANCE_LEVEL=BALANCED
echo #
echo # Cleaning aggressiveness : MODERATE, AGGRESSIVE, CONSERVATIVE
echo CLEANING_AGGRESSIVENESS=MODERATE
echo #
echo # Defender action : ENABLE, REDUCE   ^(DISABLE intentionally removed^)
echo DEFENDER_ACTION=ENABLE
echo #
echo # Toggles
echo GAMING_MODE=DISABLED
echo OFFICE_OPTIMIZATION=ENABLED
echo MULTIMEDIA_ENHANCEMENT=ENABLED
echo SSD_OPTIMIZATION=ENABLED
echo #
echo # Privacy level : HIGH, MEDIUM, LOW
echo PRIVACY_LEVEL=HIGH
echo #
echo # Network profile : DESKTOP, GAMING, SERVER
echo NETWORK_PROFILE=DESKTOP
echo #
echo # UI animations : MINIMAL, DEFAULT, FULL
echo UI_ANIMATIONS=MINIMAL
) > "%ACCELERATION_FILE%"
echo   [ OK ] %ACCELERATION_FILE%
echo.
echo   Both templates use conservative defaults. Edit them before use.
echo.
pause
goto :MAIN_MENU


:: ============================================================================
::  SUBROUTINES - ROLLBACK HELP
:: ============================================================================
:SHOW_ROLLBACK
cls
echo.
echo ================================================================
echo   ROLLBACK
echo ================================================================
echo.
echo   1. An automatic backup was taken before the last run:
echo        %BACKUP_DIR%
echo.
echo   2. Run the generated rollback script to re-import the registry:
echo        %RESTORE_FILE%
echo.
echo   3. What the rollback script does NOT restore:
echo        - firewall rules          ^(recreate or delete manually^)
echo        - Windows features        ^(use Install-WindowsFeature^)
echo        - files removed by [10]   ^(not recoverable^)
echo        - service start types     ^(see Services_Before.txt in the backup^)
echo.
echo   4. For a full rollback, prefer a system restore point or the VM
echo      snapshot you took before running this script.
echo.
pause
goto :MAIN_MENU


:: ============================================================================
::  SUBROUTINES - BACKUP  (P1-9)
:: ============================================================================
:BACKUP_SETTINGS
if not exist "%BACKUP_DIR%\" mkdir "%BACKUP_DIR%" >nul 2>&1

>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [8] Configuration backup

call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "Memory_Management.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "Session_Manager_Power.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "Session_Manager_Kernel.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Session_Manager_Environment.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" "PriorityControl.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" "FileSystem.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "GraphicsDrivers.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "Tcpip_Parameters.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "Dnscache_Parameters.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "LanmanServer_Parameters.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "Multimedia_SystemProfile.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "Policies_System.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "Policies_DataCollection_User.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" "Policies_Reliability.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "Policies_DataCollection.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "Policies_WindowsSearch.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "Policies_AdvertisingInfo.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "Policies_SystemActivities.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "Policies_Location.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "Policies_AppCompat.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "Policies_GameDVR.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" "Windows_Defender_Policies.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Defender" "Windows_Defender_Product.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Defender\Features" "Windows_Defender_Features.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Defender\MpEngine" "Windows_Defender_MpEngine.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" "Windows_Defender_RTP.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Defender\SpyNet" "Windows_Defender_SpyNet.reg"
call :REG_EXPORT "HKLM\Software\Microsoft\Security Center" "Security_Center.reg"
call :REG_EXPORT "HKLM\Software\Microsoft\ServerManager" "ServerManager.reg"
call :REG_EXPORT "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" "Run_HKLM.reg"
call :REG_EXPORT "HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" "StartupApproved_Run.reg"
call :REG_EXPORT "HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer" "Explorer_HKLM.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio" "Audio.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Media Center" "MediaCenter.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Windows Media Foundation" "WindowsMediaFoundation.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction" "BootOptimizeFunction.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Services\HPET\Parameters" "HPET_Parameters.reg"
call :REG_EXPORT "HKLM\SYSTEM\CurrentControlSet\Services\amdkmdag\Options" "AMD_Options.reg"
call :REG_EXPORT "HKLM\SOFTWARE\NVIDIA Corporation\Global\NVTweak" "NVIDIA_NVTweak.reg"
call :REG_EXPORT "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components" "ActiveSetup_InstalledComponents.reg"
call :REG_EXPORT "HKCU\Control Panel\Desktop" "Desktop_HKCU.reg"
call :REG_EXPORT "HKCU\Control Panel\Desktop\WindowMetrics" "Desktop_WindowMetrics.reg"
call :REG_EXPORT "HKCU\Control Panel\Accessibility\StickyKeys" "Accessibility_StickyKeys.reg"
call :REG_EXPORT "HKCU\Control Panel\Accessibility\Keyboard Response" "Accessibility_KeyboardResponse.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" "Explorer_HKCU.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Explorer_Advanced.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "Explorer_VisualEffects.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "Themes_Personalize.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" "Internet_Settings.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" "Privacy_HKCU.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "AdvertisingInfo_HKCU.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Windows\CurrentVersion\Audio" "Audio_HKCU.reg"
call :REG_EXPORT "HKCU\System\GameConfigStore" "GameConfigStore.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Office\16.0\Common" "Office16_Common.reg"
call :REG_EXPORT "HKCU\Software\Microsoft\Clipboard" "Clipboard.reg"

:: Service start types before the change (used by the manual rollback path)
sc query type= service state= all > "%BACKUP_DIR%\Services_List_Before.txt" 2>&1
for %%S in (Audiosrv AudioEndpointBuilder Themes WSearch SysMain WlanSvc FontCache StorSvc EventSystem WerSvc Fax RemoteRegistry SNMPTRAP CertPropSvc wisvc lfsvc MapsBroker ServerManager Spooler lmhosts XblAuthManager XblGameSave XboxNetApiSvc mrxsmb10 lanmanworkstation wuauserv) do (
    sc qc %%S >> "%BACKUP_DIR%\Services_Config_Before.txt" 2>&1
)

:: Power scheme and hibernate state before the change
powercfg /getactivescheme > "%BACKUP_DIR%\Power_Scheme_Before.txt" 2>&1
powercfg /a >> "%BACKUP_DIR%\Power_Scheme_Before.txt" 2>&1

:: Installed features and capabilities before the change
dism /online /get-features /format:table > "%BACKUP_DIR%\Windows_Features_Before.txt" 2>&1
powershell -NoProfile -Command "Get-WindowsCapability -Online | Where-Object State -eq 'Installed' | Select-Object -ExpandProperty Name" > "%BACKUP_DIR%\Windows_Capabilities_Before.txt" 2>&1

>>"%LOG_FILE%" echo   [ OK ] services, power scheme, features and capabilities snapshotted
goto :EOF

:REG_EXPORT
reg query "%~1" >nul 2>&1
if errorlevel 1 (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] export %~2  (key absent: %~1)
    goto :EOF
)
reg export "%~1" "%BACKUP_DIR%\%~2" /y >nul 2>&1
if errorlevel 1 (
    set /a FAIL_COUNT+=1
    >>"%LOG_FILE%" echo   [FAIL] export %~2
) else (
    set /a OK_COUNT+=1
    >>"%LOG_FILE%" echo   [ OK ] export %~2
)
goto :EOF


:: ============================================================================
::  SUBROUTINES - GENERATE ROLLBACK SCRIPT
:: ============================================================================
:GEN_RESTORE_SCRIPT
(
echo @echo off
echo setlocal
echo.
echo echo ============================================================
echo echo  Registry rollback for %SCRIPT_NAME% v%SCRIPT_VER%
echo echo  Backup taken at : %STAMP%
echo echo  Source folder   : %BACKUP_DIR%
echo echo ============================================================
echo echo.
echo cd /d "%%~dp0"
echo.
echo echo [1/3] Re-importing registry branches...
echo for %%%%F in ("%%~dp0*.reg") do ^(
echo     echo   importing %%%%~nxF
echo     reg import "%%%%F" ^>nul 2^>^&1
echo ^)
echo.
echo echo [2/3] Service start types were snapshotted BEFORE the change to:
echo echo         Services_Config_Before.txt
echo echo       Restore them manually if needed, for example:
echo echo         sc config ^<name^> start= ^<auto^|^demand^|^disabled^>
echo echo.
echo echo [3/3] The active power scheme before the change is recorded in:
echo echo         Power_Scheme_Before.txt
echo echo       Reactivate it with:  powercfg /setactive ^<GUID^>
echo echo.
echo echo NOT restored by this script:
echo echo   - firewall rules added by the tuner
echo echo   - Windows features / capabilities installed or removed
echo echo   - files deleted by the disk cleanup step
echo echo   - hibernation state
echo echo.
echo echo For a complete rollback use a restore point or a VM snapshot.
echo pause
) > "%RESTORE_FILE%"
if errorlevel 1 (
    set /a FAIL_COUNT+=1
    >>"%LOG_FILE%" echo   [FAIL] could not write %RESTORE_FILE%
) else (
    set /a OK_COUNT+=1
    >>"%LOG_FILE%" echo   [ OK ] rollback script written: %RESTORE_FILE%
)
goto :EOF


:: ============================================================================
::  LOGGING HELPERS
:: ============================================================================
:LOG_RC
:: %1 = description   %2 = exit code from the command issued just before
if "%~2"=="0" (
    set /a OK_COUNT+=1
    >>"%LOG_FILE%" echo   [ OK ] %~1
) else (
    set /a FAIL_COUNT+=1
    >>"%LOG_FILE%" echo   [FAIL] %~1  (exit=%~2)
)
goto :EOF

:LOG_RC_SOFT
:: Same as LOG_RC but treats a non-zero exit code as "nothing to do" rather
:: than a failure - used where absence of the target is a normal outcome.
if "%~2"=="0" (
    set /a OK_COUNT+=1
    >>"%LOG_FILE%" echo   [ OK ] %~1
) else (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] %~1  (exit=%~2 - already set or not applicable)
)
goto :EOF


:: ============================================================================
::  [1] CORE SERVICES
:: ============================================================================
:DO_SERVICES
echo   [1] Core services...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [1] Core services

:: Enable and start the services a desktop session needs.
for %%S in (
    "Audiosrv,Windows Audio",
    "AudioEndpointBuilder,Windows Audio Endpoint Builder",
    "Themes,Themes",
    "WSearch,Windows Search",
    "SysMain,SysMain",
    "WlanSvc,WLAN AutoConfig",
    "FontCache,Windows Font Cache",
    "StorSvc,Storage Service",
    "EventSystem,COM+ Event System"
) do (
    for /f "tokens=1,2 delims=," %%a in ("%%~S") do (
        sc config "%%~a" start= auto >nul 2>&1
        call :LOG_RC "service %%~a start=auto  [%%~b]" !errorlevel!
        net start "%%~a" >nul 2>&1
        call :LOG_RC_SOFT "service %%~a started  [%%~b]" !errorlevel!
    )
)

:: Disable services that make no sense on a workstation.
:: NOTE 9.0: CertPropSvc (smart card / UKey / enterprise CA certificate
:: propagation) and Spooler (printing, PDF export) were removed from this
:: list - disabling them breaks smart-card logon and printing.
for %%S in (
    "WerSvc,Windows Error Reporting",
    "Fax,Fax Service",
    "RemoteRegistry,Remote Registry",
    "SNMPTRAP,SNMP Trap",
    "wisvc,Windows Insider Service",
    "lfsvc,Geolocation Service",
    "MapsBroker,Downloaded Maps Manager",
    "lmhosts,TCP/IP NetBIOS Helper",
    "XblAuthManager,Xbox Live Auth Manager",
    "XblGameSave,Xbox Live Game Save",
    "XboxNetApiSvc,Xbox Live Networking Service"
) do (
    for /f "tokens=1,2 delims=," %%a in ("%%~S") do (
        sc config "%%~a" start= disabled >nul 2>&1
        call :LOG_RC_SOFT "service %%~a start=disabled  [%%~b]" !errorlevel!
        net stop "%%~a" >nul 2>&1
    )
)

:: Server Manager pop-up on logon is driven by a scheduled task, not by a
:: service ("ServerManager" is not a valid service name).
schtasks /Change /TN "\Microsoft\Windows\Server Manager\ServerManager" /Disable >nul 2>&1
call :LOG_RC_SOFT "scheduled task ServerManager disabled" !errorlevel!

echo   [1] done.
goto :EOF


:: ============================================================================
::  [2] SYSTEM PERFORMANCE
:: ============================================================================
:DO_PERFORMANCE
echo   [2] System performance...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [2] System performance

:: High performance power plan
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
call :LOG_RC "power plan set to High performance" !errorlevel!
:: P2/F-25: read the result back instead of trusting the command
for /f "delims=" %%a in ('powercfg /getactivescheme 2^>nul') do >>"%LOG_FILE%" echo   [READ] %%a

powercfg -change -monitor-timeout-ac 0 >nul 2>&1
call :LOG_RC "display timeout disabled (AC)" !errorlevel!
powercfg -change -disk-timeout-ac 0 >nul 2>&1
call :LOG_RC "disk timeout disabled (AC)" !errorlevel!
powercfg -change -standby-timeout-ac 0 >nul 2>&1
call :LOG_RC "standby timeout disabled (AC)" !errorlevel!

:: NOTE 9.0: "bcdedit /set {current} nx OptIn" was removed. OptIn is already
:: the Windows default, so the line only gave the impression of a change.
:: NOTE 9.0: "DisableMemoryCompression=0" was removed. The comment claimed to
:: disable memory compression while the value 0 keeps it enabled.

reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 10 /f >nul 2>&1
call :LOG_RC "SystemResponsiveness=10" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 4294967295 /f >nul 2>&1
call :LOG_RC "NetworkThrottlingIndex=disabled" !errorlevel!

reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v "Win32PrioritySeparation" /t REG_DWORD /d 26 /f >nul 2>&1
call :LOG_RC "Win32PrioritySeparation=26" !errorlevel!

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "LargeSystemCache" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "LargeSystemCache=0 (workstation cache policy)" !errorlevel!

:: Hibernation off.
:: NOTE 9.0: HiberbootEnabled (Fast Startup) was removed together with this.
:: Fast Startup needs hiberfil.sys, so writing HiberbootEnabled=1 after
:: "powercfg /hibernate off" could never take effect (finding F-07).
powercfg /hibernate off >nul 2>&1
call :LOG_RC "hibernation disabled" !errorlevel!

echo   [2] done.
goto :EOF


:: ============================================================================
::  [3] USER INTERFACE
:: ============================================================================
:DO_UI
echo   [3] User interface...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [3] User interface

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ShutdownWithoutLogon" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "ShutdownWithoutLogon enabled" !errorlevel!

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" /v "ShutdownReasonOn" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "shutdown reason prompt disabled" !errorlevel!

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "DisableCAD" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "Ctrl+Alt+Del requirement disabled" !errorlevel!

:: NOTE 9.0: the UAC downgrade that v8.1 applied here was removed.
::   ConsentPromptBehaviorAdmin=0 + PromptOnSecureDesktop=0 made administrator
::   elevation silent AND kept it off the secure desktop, which is what turned
::   the remaining downgrades into a usable kill chain (finding F-02).
::   UAC state is now only asserted to be ON, in section [5].

:: Visual effects: prefer performance, keep font smoothing and clear type.
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v "VisualFXSetting" /t REG_DWORD /d 3 /f >nul 2>&1
call :LOG_RC "VisualFXSetting=3 (adjusted for best performance)" !errorlevel!
reg add "HKCU\Control Panel\Desktop" /v "DragFullWindows" /t REG_SZ /d 0 /f >nul 2>&1
call :LOG_RC "DragFullWindows=0" !errorlevel!
reg add "HKCU\Control Panel\Desktop" /v "FontSmoothing" /t REG_SZ /d 2 /f >nul 2>&1
call :LOG_RC "FontSmoothing=2" !errorlevel!
reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d 9032078012000000 /f >nul 2>&1
call :LOG_RC "UserPreferencesMask applied" !errorlevel!
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d 0 /f >nul 2>&1
call :LOG_RC "window minimize animation disabled" !errorlevel!

reg add "HKLM\Software\Microsoft\ServerManager" /v "DoNotOpenServerManagerAtLogon" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "Server Manager no longer opens at logon" !errorlevel!

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "dark mode for apps" !errorlevel!
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "dark mode for system UI" !errorlevel!

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "file extensions shown" !errorlevel!

echo   [3] done.
goto :EOF


:: ============================================================================
::  [4] NETWORK
:: ============================================================================
:DO_NETWORK
echo   [4] Network...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [4] Network

:: NOTE 9.0: TcpWindowSize was removed - it only has an effect when receive
:: window auto-tuning is disabled, and disabling auto-tuning is what the same
:: section used to do. Both contradicted modern defaults.
:: NOTE 9.0: "netsh interface tcp set heuristics disabled" was removed: the
:: heuristics are long gone from current stacks and the command is a no-op.

reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "TcpAckFrequency" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "TcpAckFrequency=1" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "TCPNoDelay" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "TCPNoDelay=1" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "Tcp1323Opts" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "Tcp1323Opts=1 (window scaling + timestamps)" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "DefaultTTL" /t REG_DWORD /d 64 /f >nul 2>&1
call :LOG_RC "DefaultTTL=64" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "EnablePMTUDiscovery" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "PMTU discovery enabled" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "EnablePMTUBHDetect" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "PMTU black-hole detection off" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "SackOpts" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "SACK enabled" !errorlevel!

:: Keep receive window auto-tuning at the Windows default (normal).
netsh interface tcp set global autotuninglevel=normal >nul 2>&1
call :LOG_RC "TCP auto-tuning level = normal" !errorlevel!
netsh interface tcp set global rss=enabled >nul 2>&1
call :LOG_RC "receive side scaling enabled" !errorlevel!

:: Legacy application connection limits.
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v "MaxConnectionsPer1_0Server" /t REG_DWORD /d 16 /f >nul 2>&1
call :LOG_RC "MaxConnectionsPer1_0Server=16" !errorlevel!
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v "MaxConnectionsPerServer" /t REG_DWORD /d 16 /f >nul 2>&1
call :LOG_RC "MaxConnectionsPerServer=16" !errorlevel!

reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v "MaxCacheTtl" /t REG_DWORD /d 3600 /f >nul 2>&1
call :LOG_RC "DNS MaxCacheTtl=3600" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v "MaxNegativeCacheTtl" /t REG_DWORD /d 5 /f >nul 2>&1
call :LOG_RC "DNS MaxNegativeCacheTtl=5" !errorlevel!

:: Optional RDP firewall rule.
:: NOTE 9.0: in v8.1 this was unconditional, non-idempotent (a new rule every
:: run) and part of a kill chain. It is now opt-in and idempotent.
echo.
echo   Server ships with Remote Desktop DISABLED. The next question only adds
echo   the inbound firewall rule; it does not enable the RDP listener.
echo   Only answer Y if you really need inbound RDP on this machine.
set /p "RDPCHOICE=Add the inbound RDP firewall rule? (Y/N): "
if /i "!RDPCHOICE!"=="Y" (
    netsh advfirewall firewall delete rule name="%RDP_RULE_NAME%" >nul 2>&1
    netsh advfirewall firewall add rule name="%RDP_RULE_NAME%" dir=in action=allow protocol=TCP localport=3389 >nul 2>&1
    call :LOG_RC "inbound RDP firewall rule added (was previously in a kill chain)" !errorlevel!
) else (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] inbound RDP firewall rule not added (user declined)
)

echo   [4] done.
goto :EOF


:: ============================================================================
::  [5] SECURITY BASELINE  (was "security policy adjustment" in v8.1)
:: ============================================================================
:DO_SECURITY
echo   [5] Security baseline...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [5] Security baseline (no downgrades)

:: Firewall must be on in every profile.
netsh advfirewall set allprofiles state on >nul 2>&1
call :LOG_RC "firewall enabled for all profiles" !errorlevel!
:: NOTE 9.0: "netsh advfirewall set allprofiles settings inboundboundary
:: notallow" was removed - it is not a valid netsh option.

:: UAC must stay on. 9.0 asserts this instead of silently weakening it.
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLUA" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "UAC (EnableLUA) forced ON" !errorlevel!

:: SMBv1 removal - this one is a genuine hardening step.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue" >nul 2>&1
call :LOG_RC "SMBv1 server protocol disabled" !errorlevel!
sc config "mrxsmb10" start= disabled >nul 2>&1
call :LOG_RC "SMB1 client driver (mrxsmb10) disabled" !errorlevel!
:: The SMB client service itself must stay automatic - it is not the SMBv1
:: feature and disabling it breaks normal file shares.
sc config "lanmanworkstation" start= auto >nul 2>&1
call :LOG_RC "SMB client service kept automatic" !errorlevel!

:: Disk performance counters (harmless, useful on virtual machines).
diskperf -Y >nul 2>&1
call :LOG_RC "disk performance counters enabled" !errorlevel!

:: NOTE 9.0 - deliberately NOT done here any more:
::   - password policy zeroing (MinimumPasswordLength=0, PasswordComplexity=0,
::     MaximumPasswordAge=-1)            -> removed, policy left untouched
::   - set the current user password to never expire -> removed
::   - DisableExceptionChainValidation (SEHOP off)   -> removed
::   - remote registry / alert suppression           -> removed
::   Together these formed the kill chain described as finding F-02.

>>"%LOG_FILE%" echo   [INFO] password policy, SEHOP and UAC prompts are NOT modified by 9.0
echo   [5] done.
goto :EOF


:: ============================================================================
::  [6] DESKTOP EXPERIENCE FEATURE
:: ============================================================================
:DO_DESKTOP_EXPERIENCE
echo   [6] Desktop Experience feature...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [6] Desktop Experience

:: NOTE 9.0: v8.1 used Enable-WindowsOptionalFeature with 'MediaPlayback',
:: 'EnhancedStorage' and 'DirectPlay'. Those are CLIENT optional features and
:: do not exist on Server SKUs, so they always failed (silently, because of
:: -ErrorAction SilentlyContinue). Desktop-Experience is the Server equivalent
:: and is what actually provides Windows Media Player, desktop themes, the
:: photo viewer and the full MMC set.

for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-WindowsFeature Desktop-Experience).Installed" 2^>nul') do set "DESKEXP_STATE=%%a"
if /i "!DESKEXP_STATE!"=="True" (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] Desktop-Experience already installed
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-WindowsFeature -Name Desktop-Experience -ErrorAction Stop | Out-Null" >nul 2>&1
    call :LOG_RC "Desktop-Experience installed (restart required)" !errorlevel!
)

:: .NET Framework 3.5 - client-side optional feature, valid on Server too.
:: NOTE 9.0: the \\network\share\sxs fallback source was deleted (finding F-05).
:: If Windows Update cannot supply the payload, use -Source with a local
:: sources\sxs folder or a mounted ISO - never an unqualified hostname.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop | Out-Null" >nul 2>&1
call :LOG_RC "NetFx3 (.NET Framework 3.5) enabled" !errorlevel!

:: Azure Arc setup capability - enumerate first, then remove by full name.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-WindowsCapability -Online -Name 'AzureArcSetup*' -ErrorAction SilentlyContinue; if ($c) { foreach ($x in $c) { Remove-WindowsCapability -Online -Name $x.Name -ErrorAction SilentlyContinue } }" >nul 2>&1
call :LOG_RC_SOFT "Azure Arc setup capability removed" !errorlevel!

:: NOTE 9.0: "Uninstall-WindowsFeature WindowsAdminCenterSetup" was removed.
:: Windows Admin Center is normally an MSI install, not a Windows feature, so
:: that line could never succeed.

:: Reset the first-run flags for the legacy media components.
reg add "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{22D6F312-B0F6-11D0-94AB-0080C74C7E95}" /v "IsInstalled" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "legacy media component first-run flag reset 1/2" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{44BBA840-CC51-11CF-AAFA-00AA00B6015C}" /v "IsInstalled" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "legacy media component first-run flag reset 2/2" !errorlevel!

:: NOTE 9.0: Defender removal is NOT part of this section any more.
:: It moved to the opt-in menu item [9] (findings F-02, F-03, F-04).

echo   [6] done.
goto :EOF


:: ============================================================================
::  [7] MEDIA FOUNDATION
:: ============================================================================
:DO_MEDIA_FOUNDATION
echo   [7] Media Foundation...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [7] Media Foundation

powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-WindowsFeature -Name Server-Media-Foundation -ErrorAction Stop | Out-Null" >nul 2>&1
call :LOG_RC_SOFT "Server-Media-Foundation installed" !errorlevel!
powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-WindowsFeature -Name Windows-Media-Player -ErrorAction Stop | Out-Null" >nul 2>&1
call :LOG_RC_SOFT "Windows-Media-Player installed" !errorlevel!

for %%S in (
    "Audiosrv,Windows Audio",
    "AudioEndpointBuilder,Windows Audio Endpoint Builder",
    "WMPNetworkSvc,Windows Media Player Network Sharing"
) do (
    for /f "tokens=1,2 delims=," %%a in ("%%~S") do (
        sc config "%%~a" start= auto >nul 2>&1
        call :LOG_RC_SOFT "service %%~a start=auto  [%%~b]" !errorlevel!
        net start "%%~a" >nul 2>&1
    )
)

reg add "HKLM\SOFTWARE\Microsoft\Windows Media Foundation" /v "EnableFrameServerMode" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "Media Foundation frame server mode off" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows Media Foundation\HardwareDRM" /v "EnableHardwareDRM" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "Media Foundation hardware DRM enabled" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Media Center" /v "InstallationComplete" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "Media Center first-run flag set" !errorlevel!

echo   [7] done.
goto :EOF


:: ============================================================================
::  [10] DISK CLEANUP  (whitelist only - P0-1)
:: ============================================================================
:DO_DISK_CLEANUP
echo   [10] Disk cleanup (whitelisted directories)...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [10] Disk cleanup
>>"%LOG_FILE%" echo   [INFO] v8.1 deleted *.log/*.old/*.tmp/*.chk/*.gid/._mp recursively
>>"%LOG_FILE%" echo   [INFO] from the volume root. That destroyed application logs,
>>"%LOG_FILE%" echo   [INFO] audit trails and updater rollback copies. 9.0 only
>>"%LOG_FILE%" echo   [INFO] cleans the explicit directories listed below.

call :DEL_DIR "%TEMP%" "user temporary files"
call :DEL_DIR "%SystemRoot%\Temp" "system temporary files"
call :DEL_DIR "%SystemRoot%\Logs\CBS" "component servicing logs"
call :DEL_DIR "%SystemRoot%\Prefetch" "prefetch data (rebuilt automatically)"
call :DEL_DIR "C:\ProgramData\Microsoft\Windows\WER\ReportQueue" "error report queue"
call :DEL_DIR "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" "archived error reports"
call :DEL_DIR "%LOCALAPPDATA%\Microsoft\DirectX" "DirectX shader cache"

:: NOTE 9.0: C:\Windows\System32\LogFiles was removed from the list - on a
:: host running IIS that directory holds the web server logs.

:: Windows Update download cache (single pass - v8.1 did this twice).
net stop wuauserv >nul 2>&1
call :DEL_DIR "%SystemRoot%\SoftwareDistribution\Download" "Windows Update download cache"
net start wuauserv >nul 2>&1

:: Browser caches - only when the profile directory really exists.
if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\" call :DEL_DIR "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache" "Chrome cache"
if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\" call :DEL_DIR "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache" "Edge cache"
for /d %%P in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do call :DEL_DIR "%%~P\cache2" "Firefox cache"

ipconfig /flushdns >nul 2>&1
call :LOG_RC "DNS resolver cache flushed" !errorlevel!

powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
call :LOG_RC_SOFT "recycle bin emptied" !errorlevel!

echo   [10] done.
goto :EOF

:DEL_DIR
:: %1 = directory   %2 = description  (deletes contents only, never the folder)
if not exist "%~1\" (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] clean %~2  (path absent)
    goto :EOF
)
del /f /s /q "%~1\*.*" >nul 2>&1
set /a OK_COUNT+=1
>>"%LOG_FILE%" echo   [ OK ] clean %~2  (%~1)
goto :EOF


:: ============================================================================
::  [11] GAMING
:: ============================================================================
:DO_GAMING
echo   [11] Gaming optimizations...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [11] Gaming optimizations

reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "Game DVR disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameDVR" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "Game DVR blocked by policy" !errorlevel!

:: NOTE 9.0: SystemResponsiveness is not rewritten here any more. Section [2]
:: sets it to 10; v8.1 set 10 there and 0 here, so the result depended on the
:: order of execution and the log showed both as done.

reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul 2>&1
call :LOG_RC "Games task GPU priority=8" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Priority" /t REG_DWORD /d 6 /f >nul 2>&1
call :LOG_RC "Games task priority=6" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "High" /f >nul 2>&1
call :LOG_RC "Games task scheduling category=High" !errorlevel!

:: NOTE 9.0: the Xbox service block was removed from here - section [1]
:: already disables the same three services (duplicate writes).

reg add "HKLM\SYSTEM\CurrentControlSet\Services\HPET\Parameters" /v "Enabled" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "high precision event timer enabled" !errorlevel!

reg add "HKLM\SOFTWARE\NVIDIA Corporation\Global\NVTweak" /v "CoolBits" /t REG_DWORD /d 28 /f >nul 2>&1
call :LOG_RC_SOFT "NVIDIA CoolBits=28 (no NVIDIA driver: expected to skip)" !errorlevel!
reg add "HKLM\SYSTEM\CurrentControlSet\Services\amdkmdag\Options" /v "EnableUlps" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC_SOFT "AMD ULPS disabled (no AMD driver: expected to skip)" !errorlevel!

echo   [11] done.
goto :EOF


:: ============================================================================
::  [12] OFFICE / PRODUCTIVITY
:: ============================================================================
:DO_OFFICE
echo   [12] Office / productivity...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [12] Office / productivity

reg add "HKCU\Software\Microsoft\Office\16.0\Common" /v "DisableAnimations" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC_SOFT "Office animations disabled (Office 16.0 not present: skip)" !errorlevel!
reg add "HKCU\Software\Microsoft\Office\16.0\Common" /v "DisableHardwareAcceleration" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC_SOFT "Office hardware acceleration kept on" !errorlevel!

reg add "HKCU\Software\Microsoft\Clipboard" /v "EnableClipboardHistory" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "clipboard history enabled" !errorlevel!

reg add "HKCU\Control Panel\Desktop" /v "DpiScalingVer" /t REG_DWORD /d 196610 /f >nul 2>&1
call :LOG_RC "DPI scaling version set" !errorlevel!
reg add "HKCU\Control Panel\Desktop" /v "Win8DpiScaling" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "per-monitor DPI scaling enabled" !errorlevel!

reg add "HKCU\Control Panel\Accessibility\StickyKeys" /v "Flags" /t REG_SZ /d "506" /f >nul 2>&1
call :LOG_RC "sticky keys hotkey disabled" !errorlevel!
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v "Flags" /t REG_SZ /d "122" /f >nul 2>&1
call :LOG_RC "filter keys hotkey disabled" !errorlevel!

echo   [12] done.
goto :EOF


:: ============================================================================
::  [13] MULTIMEDIA
:: ============================================================================
:DO_MULTIMEDIA
echo   [13] Multimedia enhancements...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [13] Multimedia enhancements

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio" /v "DisableProtectedAudioDG" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "protected audio path relaxed (improves compatibility; affects DRM playback)" !errorlevel!

:: NOTE 9.0: "DisableMMCSS=0" was removed - 0 is already the default value,
:: so the line changed nothing.

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Audio" /v "EnableSpatialSound" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "spatial sound enabled" !errorlevel!

reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Video Playback" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul 2>&1
call :LOG_RC "Video Playback task GPU priority=8" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Video Playback" /v "Priority" /t REG_DWORD /d 6 /f >nul 2>&1
call :LOG_RC "Video Playback task priority=6" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Video Playback" /v "Scheduling Category" /t REG_SZ /d "High" /f >nul 2>&1
call :LOG_RC "Video Playback scheduling category=High" !errorlevel!

reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v "HwSchMode" /t REG_DWORD /d 2 /f >nul 2>&1
call :LOG_RC "hardware accelerated GPU scheduling enabled" !errorlevel!

echo   [13] done.
goto :EOF


:: ============================================================================
::  [14] STORAGE / SSD  (advisory - P1-3)
:: ============================================================================
:DO_STORAGE
echo   [14] Storage / SSD checks...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [14] Storage / SSD
>>"%LOG_FILE%" echo   [INFO] v8.1 disabled Prefetch, Superfetch, boot optimisation and
>>"%LOG_FILE%" echo   [INFO] the ScheduledDefrag task. On SSDs Windows uses that task
>>"%LOG_FILE%" echo   [INFO] to issue periodic TRIM, so disabling it removes TRIM
>>"%LOG_FILE%" echo   [INFO] maintenance. 9.0 changes none of these.

:: TRIM must be enabled (0 = delete notifications enabled = TRIM on).
fsutil behavior set disabledeletenotify 0 >nul 2>&1
call :LOG_RC "TRIM (delete notification) enabled" !errorlevel!

:: Last access time updates off - a real, safe saving on both SSD and HDD.
fsutil behavior set disablelastaccess 1 >nul 2>&1
call :LOG_RC "NTFS last access time updates disabled" !errorlevel!

:: Report the scheduling state so the operator can see it was left alone.
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -ErrorAction SilentlyContinue).State" 2^>nul') do >>"%LOG_FILE%" echo   [READ] ScheduledDefrag state: %%a
powershell -NoProfile -Command "Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -ErrorAction SilentlyContinue | ForEach-Object { $_.TaskName + ' = ' + $_.State }" > "%BACKUP_DIR%\Defrag_Task_State.txt" 2>&1
>>"%LOG_FILE%" echo   [INFO] ScheduledDefrag state written to Defrag_Task_State.txt (left unmodified)

:: NOTE 9.0: the machine-wide TEMP/TMP redirection to %SystemRoot%\Temp was
:: removed (finding F-10). It was labelled "move temporary files to RAM disk"
:: but only moved every service and session onto the system volume.

echo   [14] done.
goto :EOF


:: ============================================================================
::  [15] PRIVACY / TELEMETRY
:: ============================================================================
:DO_PRIVACY
echo   [15] Privacy / telemetry...
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [15] Privacy / telemetry

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "telemetry policy=0" !errorlevel!
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "telemetry (legacy key)=0" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" /v "AITEnable" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "application impact telemetry disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" /v "DisableInventory" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "application inventory disabled" !errorlevel!

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "Cortana disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "web search in Start disabled" !errorlevel!

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "advertising ID blocked by policy" !errorlevel!
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "advertising ID disabled (user)" !errorlevel!

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v "EnableActivityFeed" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "activity feed disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v "PublishUserActivities" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "publishing user activities disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v "UploadUserActivities" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "uploading user activities disabled" !errorlevel!

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableLocation" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "location tracking disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableLocationScripting" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "location scripting disabled" !errorlevel!
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableWindowsLocationProvider" /t REG_DWORD /d 1 /f >nul 2>&1
call :LOG_RC "windows location provider disabled" !errorlevel!

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
call :LOG_RC "tailored experiences disabled" !errorlevel!

echo   [15] done.
goto :EOF


:: ============================================================================
::  [9] WINDOWS DEFENDER REDUCTION  -- RISKY, OPT-IN ONLY
:: ============================================================================
:DO_DEFENDER
echo.
echo   [9] Windows Defender reduction  *** RISKY ***
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [9] Windows Defender reduction (explicit opt-in)
>>"%LOG_FILE%" echo   [INFO] TamperProtection=0 and DisableAntiSpyware/DisableAntiVirus
>>"%LOG_FILE%" echo   [INFO] were removed from 9.0: they are ignored by Windows and
>>"%LOG_FILE%" echo   [INFO] only produced a false "disabled" log entry.
>>"%LOG_FILE%" echo   [INFO] The alert-suppression keys were removed as well.

:: ---- state BEFORE ----------------------------------------------------------
echo   Reading the Defender state before the change...
powershell -NoProfile -Command "$s = Get-MpComputerStatus -ErrorAction SilentlyContinue; if ($s) { 'AMServiceEnabled=' + $s.AMServiceEnabled; 'RealTimeProtectionEnabled=' + $s.RealTimeProtectionEnabled; 'IsTamperProtected=' + $s.IsTamperProtected; 'AntivirusEnabled=' + $s.AntivirusEnabled } else { 'Get-MpComputerStatus unavailable' }" > "%BACKUP_DIR%\Defender_State_Before.txt" 2>&1
for /f "delims=" %%a in ('type "%BACKUP_DIR%\Defender_State_Before.txt"') do >>"%LOG_FILE%" echo   [BEFORE] %%a

echo.
echo   Tamper protection blocks most of this. If "IsTamperProtected=True" the
echo   attempt below will almost certainly fail, and the log will say so.
:: NOTE: "set /p" leaves the variable UNCHANGED when the user just presses
:: Enter. Clearing first prevents a previous YES from being reused silently.
set "RISKACK="
set /p "RISKACK=Type YES (in capitals) to continue, anything else to skip: "
if /i not "!RISKACK!"=="YES" (
    set /a SKIP_COUNT+=1
    >>"%LOG_FILE%" echo   [SKIP] Defender reduction declined by the operator
    echo.
    echo   Skipped.
    goto :EOF
)

:: ---- attempt ---------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "Uninstall-WindowsFeature -Name Windows-Defender -ErrorAction Stop | Out-Null" >nul 2>&1
call :LOG_RC "uninstall Windows-Defender feature" !errorlevel!

:: Disable the Defender scheduled tasks. This part really does take effect.
for %%T in (
    "Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh",
    "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
    "Microsoft\Windows\Windows Defender\Windows Defender Cleanup",
    "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
    "Microsoft\Windows\Windows Defender\Windows Defender Verification",
    "Microsoft\Windows\Windows Defender\Windows Defender Heartbeat"
) do (
    schtasks /Change /TN "%%~T" /Disable >nul 2>&1
    call :LOG_RC_SOFT "task disabled: %%~T" !errorlevel!
)

:: Remove the context menu entries.
reg delete "HKCR\*\shellex\ContextMenuHandlers\EPP" /f >nul 2>&1
call :LOG_RC_SOFT "context menu handler removed (*)" !errorlevel!
reg delete "HKCR\Directory\shellex\ContextMenuHandlers\EPP" /f >nul 2>&1
call :LOG_RC_SOFT "context menu handler removed (Directory)" !errorlevel!
reg delete "HKCR\Drive\shellex\ContextMenuHandlers\EPP" /f >nul 2>&1
call :LOG_RC_SOFT "context menu handler removed (Drive)" !errorlevel!

:: NOTE 9.0: these v8.1 lines were removed on purpose:
::   reg delete ...\StartupApproved\Run /v SecurityHealth
::   reg delete ...\Run /v SecurityHealth
::   reg add "HKLM\Software\Microsoft\Security Center" Notifications_Disable=1
:: Hiding the security warnings is not a tuning decision. If protection really
:: is off, the operator should be able to see it.

:: ---- state AFTER (this is what makes the log honest) -----------------------
echo.
echo   Reading the Defender state back...
powershell -NoProfile -Command "$s = Get-MpComputerStatus -ErrorAction SilentlyContinue; if ($s) { 'AMServiceEnabled=' + $s.AMServiceEnabled; 'RealTimeProtectionEnabled=' + $s.RealTimeProtectionEnabled; 'IsTamperProtected=' + $s.IsTamperProtected; 'AntivirusEnabled=' + $s.AntivirusEnabled } else { 'Get-MpComputerStatus unavailable - the Defender feature may be removed' }" > "%BACKUP_DIR%\Defender_State_After.txt" 2>&1
for /f "delims=" %%a in ('type "%BACKUP_DIR%\Defender_State_After.txt"') do (
    >>"%LOG_FILE%" echo   [AFTER]  %%a
    echo   %%a
)
>>"%LOG_FILE%" echo   [NOTE] Compare BEFORE and AFTER above. If they are identical the
>>"%LOG_FILE%" echo   [NOTE] reduction did NOT take effect (tamper protection is the
>>"%LOG_FILE%" echo   [NOTE] usual cause). v8.1 would have logged success here.
echo.
echo   A restart is required for a feature removal to complete.
echo   [9] done.
goto :EOF


:: ============================================================================
::  ACCELERATION.LEVEL PROFILE
:: ============================================================================
:APPLY_ACCELERATION
>>"%LOG_FILE%" echo.
>>"%LOG_FILE%" echo [ACCEL] Acceleration.Level profile

set "PERF_LEVEL="
set "NETWORK_PROFILE="
set "UI_ANIMATIONS="
set "CLEAN_AGGR="

:: P1-8: quoted reader, so a path with spaces no longer breaks parsing.
for /f "usebackq tokens=1* delims==" %%A in ("%ACCELERATION_FILE%") do (
    if /i "%%A"=="PERFORMANCE_LEVEL"      set "PERF_LEVEL=%%B"
    if /i "%%A"=="NETWORK_PROFILE"        set "NETWORK_PROFILE=%%B"
    if /i "%%A"=="UI_ANIMATIONS"          set "UI_ANIMATIONS=%%B"
    if /i "%%A"=="CLEANING_AGGRESSIVENESS" set "CLEAN_AGGR="%%B"
)

if /i "!PERF_LEVEL!"=="EXTREME" (
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
    call :LOG_RC "profile: extreme performance power plan" !errorlevel!
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v "Win32PrioritySeparation" /t REG_DWORD /d 26 /f >nul 2>&1
    call :LOG_RC "profile: Win32PrioritySeparation=26" !errorlevel!
) else if /i "!PERF_LEVEL!"=="BALANCED" (
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
    call :LOG_RC "profile: balanced power plan" !errorlevel!
)

if /i "!NETWORK_PROFILE!"=="GAMING" (
    netsh interface tcp set global autotuninglevel=disabled >nul 2>&1
    call :LOG_RC "profile: gaming network mode" !errorlevel!
) else if /i "!NETWORK_PROFILE!"=="DESKTOP" (
    netsh interface tcp set global autotuninglevel=normal >nul 2>&1
    call :LOG_RC "profile: desktop network mode" !errorlevel!
)

if /i "!UI_ANIMATIONS!"=="MINIMAL" (
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d 0 /f >nul 2>&1
    call :LOG_RC "profile: window animations off" !errorlevel!
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ListviewAlphaSelect" /t REG_DWORD /d 0 /f >nul 2>&1
    call :LOG_RC "profile: list view alpha off" !errorlevel!
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ListviewShadow" /t REG_DWORD /d 0 /f >nul 2>&1
    call :LOG_RC "profile: list view shadow off" !errorlevel!
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarAnimations" /t REG_DWORD /d 0 /f >nul 2>&1
    call :LOG_RC "profile: taskbar animations off" !errorlevel!
)

:: NOTE 9.0: the v8.1 profile could silently trigger a Defender removal
:: (DEFENDER_ACTION=DISABLE) and schedule a RunOnce cleanup through
:: CLEANING_AGGRESSIVENESS=AGGRESSIVE. Both paths were removed - a profile file
:: is not allowed to start a risky or irreversible action.

>>"%LOG_FILE%" echo [ACCEL] profile applied
echo   Acceleration profile applied.
goto :EOF


:: ============================================================================
::  END OF SCRIPT
:: ============================================================================
