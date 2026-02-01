<#
.SYNOPSIS
    Installs and configures CNC File Sync for Windows.

.DESCRIPTION
    This script:
    - Downloads sync scripts from the FTP server automatically
    - Configures sync settings (source folder, schedule, etc.)
    - Sets up Windows Task Scheduler for automated sync
    - Can be re-run to update settings

.PARAMETER ServerIP
    IP address or hostname of the FTP server.

.PARAMETER ConfigOnly
    Skip file download, only update configuration and schedule.

.PARAMETER Uninstall
    Remove the scheduled task (does not delete files).

.EXAMPLE
    .\Install-CncSync.ps1 -ServerIP 192.168.1.66
    Install with specified server IP.

.EXAMPLE
    .\Install-CncSync.ps1 -ConfigOnly
    Update schedule/settings without downloading files.
#>

[CmdletBinding()]
param(
    [string]$ServerIP,
    [switch]$ConfigOnly,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "sync-config.ps1"
$LogFile = Join-Path $ScriptDir "install.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logLine
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN"  { Write-Host $Message -ForegroundColor Yellow }
        "OK"    { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message }
    }
}

function Read-HostWithDefault {
    param([string]$Prompt, [string]$Default)
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-WinScp {
    param([string]$PreferredPath)

    # Check preferred path first
    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    # Check same directory as script
    $localPath = Join-Path $ScriptDir "WinSCP.com"
    if (Test-Path $localPath) {
        return $localPath
    }

    # Check Program Files
    $progFiles = @(
        "${env:ProgramFiles}\WinSCP\WinSCP.com",
        "${env:ProgramFiles(x86)}\WinSCP\WinSCP.com"
    )
    foreach ($path in $progFiles) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Get-HostKey {
    param([string]$WinScpPath, [string]$Host)

    Write-Log "Retrieving host key from $Host..."

    # Create a temporary script to get the host key
    $tempScript = [System.IO.Path]::GetTempFileName()
    try {
        @"
open sftp://publisher@$Host/
exit
"@ | Set-Content $tempScript

        $output = & $WinScpPath /script=$tempScript /log=NUL 2>&1 | Out-String

        # Look for the host key in the output
        if ($output -match 'ssh-ed25519\s+\d+\s+[\w/+=]+') {
            return $Matches[0]
        }
        elseif ($output -match 'ssh-rsa\s+\d+\s+[\w/+=]+') {
            return $Matches[0]
        }
    }
    finally {
        Remove-Item $tempScript -ErrorAction SilentlyContinue
    }

    return $null
}

function Convert-SshKeyToPpk {
    param([string]$WinScpPath, [string]$SshKeyPath, [string]$PpkPath)

    if (Test-Path $PpkPath) {
        Write-Log "PPK key already exists: $PpkPath"
        return $true
    }

    if (-not (Test-Path $SshKeyPath)) {
        Write-Log "SSH key not found: $SshKeyPath" -Level "ERROR"
        return $false
    }

    Write-Log "Converting SSH key to PPK format..."
    $result = & $WinScpPath /keygen $SshKeyPath /output=$PpkPath 2>&1

    if (Test-Path $PpkPath) {
        Write-Log "Created PPK key: $PpkPath" -Level "OK"
        return $true
    }
    else {
        Write-Log "Failed to convert key: $result" -Level "ERROR"
        return $false
    }
}

function Download-FilesFromServer {
    param(
        [string]$ServerIP,
        [string]$KeyPath,
        [string]$DestDir
    )

    $remotePath = "/opt/cnc-ftp-server/windows"
    $filesToDownload = @(
        "SyncCncToFtp.ps1",
        "SyncCncToFtp.cmd",
        "sync-config.ps1"
    )

    Write-Log "Downloading sync files from server..."

    $downloadedCount = 0
    foreach ($file in $filesToDownload) {
        $localPath = Join-Path $DestDir $file
        $remoteFull = "ftpadmin@${ServerIP}:${remotePath}/${file}"

        # Skip config file if it already exists (preserve user settings)
        if ($file -eq "sync-config.ps1" -and (Test-Path $localPath)) {
            Write-Log "  Skipping $file (preserving existing config)"
            continue
        }

        Write-Log "  Downloading $file..."
        $scpArgs = @("-i", $KeyPath, "-o", "StrictHostKeyChecking=accept-new", $remoteFull, $localPath)

        try {
            $result = & scp @scpArgs 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path $localPath)) {
                Write-Log "  Downloaded: $file" -Level "OK"
                $downloadedCount++
            }
            else {
                Write-Log "  Failed to download $file : $result" -Level "WARN"
            }
        }
        catch {
            Write-Log "  Error downloading $file : $_" -Level "WARN"
        }
    }

    return $downloadedCount
}

function Install-ScheduledTask {
    param([hashtable]$Config)

    $taskName = $Config.TaskName

    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Log "Removing existing scheduled task..."
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    if (-not $Config.EnableSchedule) {
        Write-Log "Scheduled task disabled in config." -Level "WARN"
        return
    }

    Write-Log "Creating scheduled task: $taskName"

    # Build the action
    $syncScript = Join-Path $ScriptDir "SyncCncToFtp.ps1"
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$syncScript`"",
        "-SftpHost", $Config.SftpHost,
        "-HostKey", "`"$($Config.HostKey)`"",
        "-SourcePath", "`"$($Config.SourcePath)`"",
        "-RemotePath", "`"$($Config.RemotePath)`"",
        "-SshKeyPath", "`"$($Config.SshKeyPath)`""
    )

    if ($Config.WinScpPath) {
        $arguments += @("-WinScpPath", "`"$($Config.WinScpPath)`"")
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument ($arguments -join " ") `
        -WorkingDirectory $ScriptDir

    # Build the trigger (repeat every X minutes)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $Config.SyncIntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 9999)

    # Build settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries:$Config.AllowBattery `
        -DontStopIfGoingOnBatteries:$Config.AllowBattery `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    # Build principal (run as current user)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited

    # Register the task
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $Config.TaskDescription | Out-Null

    Write-Log "Scheduled task created successfully" -Level "OK"
    Write-Log "  Interval: Every $($Config.SyncIntervalMinutes) minutes"
    Write-Log "  Source: $($Config.SourcePath)"
    Write-Log "  Destination: $($Config.SftpHost):$($Config.RemotePath)"
}

function Remove-ScheduledTask {
    param([string]$TaskName)

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Scheduled task '$TaskName' removed." -Level "OK"
    }
    else {
        Write-Log "Scheduled task '$TaskName' not found." -Level "WARN"
    }
}

function Save-Config {
    param([hashtable]$Config)

    $content = @"
# CNC Sync Configuration
# Edit these values and re-run Install-CncSync.ps1 to apply changes

# FTP Server Settings
`$Config = @{
    # IP address or hostname of the FTP server
    SftpHost = "$($Config.SftpHost)"

    # SSH host key (run WinSCP once manually to get this, or leave empty to prompt)
    # Format: "ssh-ed25519 256 XXXXXXXXXX..."
    HostKey = "$($Config.HostKey)"

    # Local folder to sync TO the server (source)
    SourcePath = "$($Config.SourcePath)"

    # Remote folder on server (destination)
    RemotePath = "$($Config.RemotePath)"

    # Path to SSH private key for publisher user
    SshKeyPath = "$($Config.SshKeyPath)"

    # Schedule Settings
    # Set to `$true to enable scheduled sync
    EnableSchedule = `$$($Config.EnableSchedule.ToString().ToLower())

    # Sync interval in minutes (e.g., 5, 10, 15, 30, 60)
    SyncIntervalMinutes = $($Config.SyncIntervalMinutes)

    # Task Scheduler settings
    TaskName = "$($Config.TaskName)"
    TaskDescription = "$($Config.TaskDescription)"

    # Run task even when on battery power
    AllowBattery = `$$($Config.AllowBattery.ToString().ToLower())

    # WinSCP paths (auto-detected if in same folder as scripts)
    WinScpPath = "$($Config.WinScpPath)"
}
"@

    Set-Content -Path $ConfigFile -Value $content
    Write-Log "Configuration saved to: $ConfigFile" -Level "OK"
}

# ============================================================================
# Main Installation Logic
# ============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CNC File Sync - Windows Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize log
"=== CNC Sync Installation Log ===" | Set-Content $LogFile
Write-Log "Installation started"
Write-Log "Script directory: $ScriptDir"

# Handle uninstall
if ($Uninstall) {
    Write-Log "Uninstall mode"
    if (Test-Path $ConfigFile) {
        . $ConfigFile
        Remove-ScheduledTask -TaskName $Config.TaskName
    }
    else {
        Remove-ScheduledTask -TaskName "CNC File Sync"
    }
    Write-Host ""
    Write-Host "Uninstall complete. Files remain in $ScriptDir" -ForegroundColor Green
    exit 0
}

# Load existing config or create default
if (Test-Path $ConfigFile) {
    Write-Log "Loading existing configuration..."
    . $ConfigFile
}
else {
    Write-Log "No configuration found, using defaults..."
    $Config = @{
        SftpHost = ""
        HostKey = ""
        SourcePath = "C:\CNC\Jobs"
        RemotePath = "/cnc-files"
        SshKeyPath = "C:\CNC\Sync\keys\publisher_ed25519.ppk"
        EnableSchedule = $true
        SyncIntervalMinutes = 5
        TaskName = "CNC File Sync"
        TaskDescription = "Synchronizes CNC files to FTP server"
        AllowBattery = $true
        WinScpPath = ""
    }
}

# Use -ServerIP parameter if provided
if ($ServerIP) {
    $Config.SftpHost = $ServerIP
}

# Download files from server (unless -ConfigOnly)
if (-not $ConfigOnly) {
    Write-Host "Server Connection" -ForegroundColor Yellow
    Write-Host "-----------------"

    # Get server IP first
    $defaultHost = if ($Config.SftpHost) { $Config.SftpHost } else { "" }
    $Config.SftpHost = Read-HostWithDefault "FTP Server IP/hostname" $defaultHost
    if ([string]::IsNullOrWhiteSpace($Config.SftpHost)) {
        Write-Log "Server IP is required." -Level "ERROR"
        exit 1
    }

    # Check for ftpadmin SSH key
    $ftpadminKey = "C:\CNC\Sync\keys\ftpadmin_ed25519"
    if (-not (Test-Path $ftpadminKey)) {
        Write-Host ""
        Write-Host "ftpadmin SSH key not found at: $ftpadminKey" -ForegroundColor Yellow
        Write-Host "This key is needed to download files from the server."
        Write-Host ""
        $customKey = Read-Host "Enter path to ftpadmin key (or press Enter to skip download)"
        if ($customKey -and (Test-Path $customKey)) {
            $ftpadminKey = $customKey
        }
        else {
            Write-Log "Skipping file download - ftpadmin key not available" -Level "WARN"
            Write-Host ""
            Write-Host "Please ensure these files are in ${ScriptDir}:" -ForegroundColor Yellow
            Write-Host "  - SyncCncToFtp.ps1"
            Write-Host "  - sync-config.ps1 (optional)"
            Write-Host ""
            $ftpadminKey = $null
        }
    }

    # Download files if we have the key
    if ($ftpadminKey) {
        $downloadCount = Download-FilesFromServer -ServerIP $Config.SftpHost -KeyPath $ftpadminKey -DestDir $ScriptDir
        if ($downloadCount -gt 0) {
            Write-Log "Downloaded $downloadCount file(s) from server" -Level "OK"
        }
    }

    Write-Host ""
}

# Interactive configuration
Write-Host "Configuration" -ForegroundColor Yellow
Write-Host "-------------"

# Server IP (may already be set above, but allow editing)
$Config.SftpHost = Read-HostWithDefault "FTP Server IP/hostname" $Config.SftpHost
if ([string]::IsNullOrWhiteSpace($Config.SftpHost)) {
    Write-Log "Server IP is required." -Level "ERROR"
    exit 1
}

# Source path
$Config.SourcePath = Read-HostWithDefault "Local folder to sync" $Config.SourcePath

# Create source folder if it doesn't exist
if (-not (Test-Path $Config.SourcePath)) {
    $create = Read-Host "Folder '$($Config.SourcePath)' does not exist. Create it? [Y/n]"
    if ($create -ne "n" -and $create -ne "N") {
        New-Item -ItemType Directory -Path $Config.SourcePath -Force | Out-Null
        Write-Log "Created folder: $($Config.SourcePath)" -Level "OK"
    }
}

# Remote path
$Config.RemotePath = Read-HostWithDefault "Remote folder on server" $Config.RemotePath

# SSH Key path
$sshKeyBase = "C:\CNC\Sync\keys\publisher_ed25519"
$defaultSshKey = if ($Config.SshKeyPath) { $Config.SshKeyPath } else { "$sshKeyBase.ppk" }
$Config.SshKeyPath = Read-HostWithDefault "Path to SSH key (PPK format)" $defaultSshKey

# Check if we need to convert from OpenSSH format
$opensshKey = $Config.SshKeyPath -replace '\.ppk$', ''
if (-not (Test-Path $Config.SshKeyPath) -and (Test-Path $opensshKey)) {
    Write-Log "Found OpenSSH key, will convert to PPK format"
}

# Schedule settings
$scheduleInput = Read-HostWithDefault "Enable scheduled sync? (yes/no)" $(if ($Config.EnableSchedule) { "yes" } else { "no" })
$Config.EnableSchedule = $scheduleInput -eq "yes" -or $scheduleInput -eq "y"

if ($Config.EnableSchedule) {
    $intervalInput = Read-HostWithDefault "Sync interval in minutes" $Config.SyncIntervalMinutes
    $Config.SyncIntervalMinutes = [int]$intervalInput
}

Write-Host ""

# Find WinSCP
Write-Log "Locating WinSCP..."
$winscpPath = Find-WinScp -PreferredPath $Config.WinScpPath

if (-not $winscpPath) {
    Write-Host ""
    Write-Host "WinSCP not found!" -ForegroundColor Red
    Write-Host "Please download WinSCP portable from:"
    Write-Host "  https://winscp.net/download/WinSCP-6.5.5-Portable.zip" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Extract WinSCP.com and WinSCP.exe to: $ScriptDir"
    Write-Host ""
    $customPath = Read-Host "Or enter path to WinSCP.com (leave blank to exit)"
    if ([string]::IsNullOrWhiteSpace($customPath)) {
        exit 1
    }
    if (Test-Path $customPath) {
        $winscpPath = $customPath
    }
    else {
        Write-Log "WinSCP not found at: $customPath" -Level "ERROR"
        exit 1
    }
}

$Config.WinScpPath = $winscpPath
Write-Log "Using WinSCP: $winscpPath" -Level "OK"

# Convert SSH key if needed
$opensshKey = $Config.SshKeyPath -replace '\.ppk$', ''
if (-not (Test-Path $Config.SshKeyPath)) {
    if (Test-Path $opensshKey) {
        Convert-SshKeyToPpk -WinScpPath $winscpPath -SshKeyPath $opensshKey -PpkPath $Config.SshKeyPath
    }
    else {
        Write-Log "SSH key not found: $($Config.SshKeyPath)" -Level "ERROR"
        Write-Host "Please ensure the publisher SSH key is at: $opensshKey"
        Write-Host "Or specify the correct path in the configuration."
        exit 1
    }
}

# Get host key if not set
if ([string]::IsNullOrWhiteSpace($Config.HostKey)) {
    Write-Host ""
    Write-Host "SSH Host Key Required" -ForegroundColor Yellow
    Write-Host "The host key verifies the server identity."
    Write-Host ""

    $getKey = Read-Host "Attempt to retrieve host key from server? [Y/n]"
    if ($getKey -ne "n" -and $getKey -ne "N") {
        $retrievedKey = Get-HostKey -WinScpPath $winscpPath -Host $Config.SftpHost
        if ($retrievedKey) {
            Write-Host "Retrieved host key: $retrievedKey" -ForegroundColor Green
            $accept = Read-Host "Accept this host key? [Y/n]"
            if ($accept -ne "n" -and $accept -ne "N") {
                $Config.HostKey = $retrievedKey
            }
        }
        else {
            Write-Log "Could not auto-retrieve host key" -Level "WARN"
        }
    }

    if ([string]::IsNullOrWhiteSpace($Config.HostKey)) {
        Write-Host ""
        Write-Host "To get the host key manually, run:" -ForegroundColor Yellow
        Write-Host "  $winscpPath /command `"open sftp://publisher@$($Config.SftpHost)/`" `"exit`""
        Write-Host ""
        $Config.HostKey = Read-Host "Enter the host key (ssh-ed25519 256 ...)"
    }
}

if ([string]::IsNullOrWhiteSpace($Config.HostKey)) {
    Write-Log "Host key is required for secure connection." -Level "ERROR"
    exit 1
}

# Save configuration
Write-Host ""
Save-Config -Config $Config

# Check for sync script
$syncScript = Join-Path $ScriptDir "SyncCncToFtp.ps1"
if (-not (Test-Path $syncScript)) {
    Write-Log "Sync script not found: $syncScript" -Level "ERROR"
    Write-Host "Please copy SyncCncToFtp.ps1 to $ScriptDir"
    exit 1
}

# Install scheduled task
Write-Host ""
Install-ScheduledTask -Config $Config

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration saved to:"
Write-Host "  $ConfigFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "To test the sync manually, run:"
Write-Host "  .\SyncCncToFtp.ps1 -SftpHost $($Config.SftpHost) -HostKey `"$($Config.HostKey)`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "To modify settings later:"
Write-Host "  1. Edit sync-config.ps1"
Write-Host "  2. Run .\Install-CncSync.ps1 -ConfigOnly"
Write-Host ""
Write-Host "To remove the scheduled task:"
Write-Host "  .\Install-CncSync.ps1 -Uninstall"
Write-Host ""

Write-Log "Installation completed successfully"
