# CNC Sync Configuration Sample
# Copy this file to sync-config.ps1 and edit the values below
# Run Install-CncSync.ps1 to apply changes

$Config = @{
    # FTP Server Settings
    # -------------------
    # IP address or hostname of the FTP server (REQUIRED)
    SftpHost = "192.168.1.66"

    # SSH host key fingerprint (run Install-CncSync.ps1 to auto-detect)
    # Format: "ssh-ed25519 256 XXXXXXXXXX..."
    HostKey = ""

    # Sync Paths
    # ----------
    # Local folder to sync TO the server (source)
    SourcePath = "C:\CNC\Jobs"

    # Remote folder on server (destination)
    RemotePath = "/cnc-files"

    # SSH Authentication
    # ------------------
    # Path to SSH private key for publisher user (PPK format for WinSCP)
    SshKeyPath = "C:\CNC\Sync\keys\publisher_ed25519.ppk"

    # Schedule Settings
    # -----------------
    # Set to $true to enable scheduled sync
    EnableSchedule = $true

    # Sync interval in minutes (e.g., 5, 10, 15, 30, 60)
    SyncIntervalMinutes = 5

    # Task Scheduler settings
    TaskName = "CNC File Sync"
    TaskDescription = "Synchronizes CNC files to FTP server"

    # Run task even when on battery power
    AllowBattery = $true

    # WinSCP Settings
    # ---------------
    # Path to WinSCP.com (leave empty to auto-detect in script folder)
    WinScpPath = ""
}
