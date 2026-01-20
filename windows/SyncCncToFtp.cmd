@echo off
setlocal

set SCRIPT_DIR=%~dp0
set POWERSHELL_EXE=powershell.exe

%POWERSHELL_EXE% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%SyncCncToFtp.ps1" -SftpHost <ftp-vm-ip>

endlocal
