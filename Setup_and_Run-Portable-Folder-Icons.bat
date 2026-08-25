@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"

cls
echo ============================================================
echo   Portable Folder Icons v0.1.1 - Setup / Repair / Rescan
echo ============================================================
echo.
echo   Python and a virtual environment are not required.
echo   This tool uses the Windows PowerShell included with Windows.
echo   It installs only for the current user and never needs admin.
echo.

if /i not "%OS%"=="Windows_NT" (
    echo ERROR: Portable Folder Icons supports Windows 10 and 11 only.
    set "RESULT=10"
    goto :finish
)

set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%WINDOWS_POWERSHELL%" (
    echo ERROR: Inbox Windows PowerShell could not be found.
    set "RESULT=11"
    goto :finish
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -Command "$v=$PSVersionTable.PSVersion; if($v.Major -lt 5 -or ($v.Major -eq 5 -and $v.Minor -lt 1)){exit 1}; $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 2}; if([Environment]::OSVersion.Version.Major -lt 10){exit 3}; exit 0"
set "CHECK_RESULT=%ERRORLEVEL%"
if "%CHECK_RESULT%"=="1" (
    echo ERROR: Windows PowerShell 5.1 or newer is required.
    set "RESULT=12"
    goto :finish
)
if "%CHECK_RESULT%"=="2" (
    echo ERROR: Setup is intentionally current-user only.
    echo Close this elevated window and run the batch normally, without
    echo "Run as administrator."
    set "RESULT=13"
    goto :finish
)
if "%CHECK_RESULT%"=="3" (
    echo ERROR: Windows 10 or 11 is required.
    set "RESULT=14"
    goto :finish
)
if not "%CHECK_RESULT%"=="0" (
    echo ERROR: The Windows compatibility check failed.
    set "RESULT=15"
    goto :finish
)

set "INSTALLER=%~dp0scripts\Windows\Install-PortableFolderIcons.ps1"
if not exist "%INSTALLER%" (
    echo ERROR: The repository installer script is missing.
    set "RESULT=16"
    goto :finish
)

echo Starting install/update/repair/rescan...
echo.
"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -RepositoryRoot "%~dp0."
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
    echo Setup completed successfully.
) else (
    echo Setup failed with exit code %RESULT%.
    echo Review the messages above; the previous installed runtime was kept
    echo whenever replacement could not complete safely.
)
echo.
set /p "PFI_CLOSE=Press Enter to close: "
endlocal & exit /b %RESULT%
