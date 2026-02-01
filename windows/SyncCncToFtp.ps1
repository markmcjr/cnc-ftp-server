param(
    [string]$SourcePath,
    [string]$SftpHost,
    [string]$SftpUser,
    [string]$RemotePath,
    [Alias("SshKeyPath")]
    [string]$KeyPath,
    [string]$HostKey,
    [string]$HostKeyFile,
    [string]$WinScpPath
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load config file if it exists
$configPath = Join-Path $scriptDir "sync-config.ps1"
if (Test-Path $configPath) {
    . $configPath
}

# Apply config values for any parameters not provided on command line
if (-not $SourcePath) {
    $SourcePath = if ($Config.SourcePath) { $Config.SourcePath } else { "C:\CNC\Jobs" }
}
if (-not $SftpHost) {
    $SftpHost = if ($Config.SftpHost) { $Config.SftpHost } else { "ftp-vm.local" }
}
if (-not $SftpUser) {
    $SftpUser = if ($Config.SftpUser) { $Config.SftpUser } else { "publisher" }
}
if (-not $RemotePath) {
    $RemotePath = if ($Config.RemotePath) { $Config.RemotePath } else { "/cnc-files" }
}
if (-not $KeyPath) {
    $KeyPath = if ($Config.SshKeyPath) { $Config.SshKeyPath } else { Join-Path $scriptDir "keys\publisher_ed25519.ppk" }
}
if (-not $HostKey -and $Config.HostKey) {
    $HostKey = $Config.HostKey
}
if (-not $WinScpPath -and $Config.WinScpPath) {
    $WinScpPath = $Config.WinScpPath
}
# Log files - try script dir first, fall back to temp
$logPath = Join-Path $scriptDir "SyncCncToFtp.log"
$winScpLogPath = Join-Path $env:TEMP "cnc-winscp.log"

# Test if we can write to script directory
try {
    [IO.File]::OpenWrite($logPath).Close()
} catch {
    $logPath = Join-Path $env:TEMP "SyncCncToFtp.log"
}
$winScpExe = if ($WinScpPath) { $WinScpPath } else { Join-Path $scriptDir "WinSCP.com" }
if (-not $HostKeyFile) {
    $HostKeyFile = Join-Path $scriptDir "hostkey.txt"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
if (-not (Test-Path $SourcePath)) {
    "[$timestamp] Source path missing: $SourcePath" | Out-File -FilePath $logPath -Append
    exit 1
}

if (-not (Test-Path $winScpExe)) {
    "[$timestamp] WinSCP.com not found at $winScpExe" | Out-File -FilePath $logPath -Append
    exit 1
}

if (-not $HostKey -and (Test-Path $HostKeyFile)) {
    $HostKey = (Get-Content -Raw $HostKeyFile)
}

if (-not $HostKey) {
    "[$timestamp] HostKey is required (WinSCP -hostkey value)." | Out-File -FilePath $logPath -Append
    exit 1
}

$HostKey = $HostKey -replace '[^\x20-\x7E]', ''
$HostKey = ($HostKey -replace '\s+', ' ').Trim().TrimEnd('.')

# Use temp folder for WinSCP script (avoids permission issues)
$winScpScriptPath = Join-Path $env:TEMP "cnc-winscp-script.txt"
$openCommand = 'open sftp://{0}@{1}/ -privatekey="{2}" -hostkey="{3}"' -f $SftpUser, $SftpHost, $KeyPath, $HostKey
$syncCommand = 'synchronize remote -delete "{0}" "{1}"' -f $SourcePath, $RemotePath
$scriptContent = @(
    $openCommand,
    $syncCommand,
    "exit"
)
$scriptContent | Out-File -FilePath $winScpScriptPath -Encoding ASCII -Force

"[$timestamp] Sync started (WinSCP delta upload)" | Out-File -FilePath $logPath -Encoding UTF8 -Append
"[$timestamp] HostKey used: $HostKey" | Out-File -FilePath $logPath -Encoding UTF8 -Append
& $winScpExe /log="$winScpLogPath" /ini=nul /script="$winScpScriptPath"
"[$timestamp] Sync complete" | Out-File -FilePath $logPath -Encoding UTF8 -Append
