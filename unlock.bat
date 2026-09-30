@echo off
rem ======================================================================
rem TURBO 4 PRO - Bootloader Unlock (UBL) - cmd wrapper for unlock.ps1
rem Usage from cmd:  unlock.bat [-Service] [-Preload] [-Auto] [-DryRun]
rem ======================================================================
set "PS=powershell"
where pwsh >nul 2>&1 && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0unlock.ps1" %*
