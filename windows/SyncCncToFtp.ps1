param(
    [string]$SourcePath = "C:\CNC\Jobs",
    [string]$SftpHost = "ftp-vm.local",
    [string]$SftpUser = "publisher",
    [string]$RemotePath = "/cnc-files",
    [Alias("SshKeyPath")]
    [string]$KeyPath,
    [string]$HostKey,
    [string]$HostKeyFile,
    [string]$WinScpPath
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $scriptDir "SyncCncToFtp.log"
$winScpLogPath = Join-Path $scriptDir "SyncCncToFtp.winscp.log"
$winScpExe = if ($WinScpPath) { $WinScpPath } else { Join-Path $scriptDir "WinSCP.com" }
if (-not $KeyPath) {
    $KeyPath = Join-Path $scriptDir "keys\publisher_ed25519.ppk"
}
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

$winScpScriptPath = Join-Path $scriptDir "winscp-script.txt"
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
