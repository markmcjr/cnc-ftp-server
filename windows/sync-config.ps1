# CNC Sync Configuration
# Edit these values and re-run Install-CncSync.ps1 to apply changes

# FTP Server Settings
$Config = @{
    # IP address or hostname of the FTP server
    SftpHost = ""

    # SSH host key (run WinSCP once manually to get this, or leave empty to prompt)
    # Format: "ssh-ed25519 256 XXXXXXXXXX..."
    HostKey = ""

    # Local folder to sync TO the server (source)
    SourcePath = "C:\CNC\Jobs"

    # Remote folder on server (destination)
    RemotePath = "/cnc-files"

    # Path to SSH private key for publisher user
    SshKeyPath = "C:\CNC\Sync\keys\publisher_ed25519.ppk"

    # Schedule Settings
    # Set to $true to enable scheduled sync
    EnableSchedule = $true

    # Sync interval in minutes (e.g., 5, 10, 15, 30, 60)
    SyncIntervalMinutes = 5

    # Task Scheduler settings
    TaskName = "CNC File Sync"
    TaskDescription = "Synchronizes CNC files to FTP server"

    # Run task even when on battery power
    AllowBattery = $true

    # WinSCP paths (auto-detected if in same folder as scripts)
    WinScpPath = ""
}
