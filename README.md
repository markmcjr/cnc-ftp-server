# CNC FTP Server

This repository captures the design and configuration artifacts for an internal CNC FTP server. Start with `docs/project-plan.md` for the architecture, security posture, and build guide.

## Layout
- `docs/` contains planning and operational documentation.
- `linux/` holds Linux configuration templates and scripts.
- `windows/` holds the publishing automation script for Windows.
- `firewall/` provides a human-readable policy summary.
- `docs/test-guide.md` provides a step-by-step validation checklist.
- `docs/manual-setup-guide.md` walks through manual setup without scripts.

## Usage Notes
- Configuration files are templates meant to be applied on the Debian FTP VM.
- The Windows script requires `sftp.exe` in PATH and a populated `C:\CNC\ssh_known_hosts`.

## Deployment

### VM Requirements
- **Minimum specs**: 1 vCPU, 1 GB RAM, 20 GB disk (adjust disk size based on expected CNC file storage)
- **OS**: Debian 12 (Bookworm) minimal install
- **Example VM name**: `cnc-ftp-01` or `ftp-cnc-prod`
- **Network**: Static IP recommended; note the IP for firewall rules and Windows client configuration

### Debian Installation Package Selection
During Debian installation, at the "Software selection" screen:
- **Deselect** "Debian desktop environment" and any desktop (GNOME, KDE, etc.)
- **Keep selected**: "standard system utilities"
- **Optional but recommended**: Select "SSH server" during install for easier initial setup (allows remote copy of repo files)

> **Note**: If you skip the SSH server during install, you must transfer the repository files using alternative methods (see below).

### Recommended Installation Path
For production systems, install the repository to `/opt/cnc-ftp-server/`:
```bash
sudo mkdir -p /opt/cnc-ftp-server
sudo chown $(whoami):$(whoami) /opt/cnc-ftp-server
```

This follows the [Filesystem Hierarchy Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s13.html) for add-on application packages.

### Getting the Repository onto the VM
Choose one of the following methods to place the repository at `/opt/cnc-ftp-server/`:

**Option A: SSH server installed during Debian setup (recommended)**
```bash
# From your workstation:
scp -r cnc-ftp-server/ user@<vm-ip>:/opt/

# Or clone directly on the VM:
sudo git clone <repo-url> /opt/cnc-ftp-server
sudo chown -R $(whoami):$(whoami) /opt/cnc-ftp-server
```

**Option B: No SSH server yet (manual transfer)**
- **USB drive**: Copy the repo to a USB drive, mount it on the VM, and copy to `/opt/`:
  ```bash
  sudo mount /dev/sdb1 /mnt
  sudo cp -r /mnt/cnc-ftp-server /opt/
  sudo umount /mnt
  ```
- **Shared folder (VMware/VirtualBox)**: Configure a shared folder in your hypervisor:
  ```bash
  sudo cp -r /mnt/hgfs/cnc-ftp-server /opt/
  ```

**Option C: GitHub without SSH**
```bash
# Log into the VM console directly
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/<org>/cnc-ftp-server.git /opt/cnc-ftp-server
sudo chown -R $(whoami):$(whoami) /opt/cnc-ftp-server
```

### Setup Steps
1. Ensure the repo is at `/opt/cnc-ftp-server/` using one of the methods above.
2. Review `linux/scripts/setup.env.example` and save as `linux/scripts/setup.env` if you want non-interactive setup.
3. Run `sudo bash /opt/cnc-ftp-server/linux/scripts/setup-ftp.sh` and answer the prompts.
4. Apply the firewall policy described in `firewall/rules.md` on the upstream firewall.

### Non-Interactive Setup
- Edit `linux/scripts/setup.env` with your values, then run `sudo bash linux/scripts/setup-ftp.sh linux/scripts/setup.env`.
- Set `INSTALL_PACKAGES=no` if you want to install packages manually.

### Validation
- Check `systemctl status vsftpd` and `systemctl status ssh`.
- Confirm passive ports and user allowlist match `linux/vsftpd/vsftpd.conf` and `linux/vsftpd/vsftpd.user_list`.

## SSH Setup (Windows Publisher)
1. Create a folder for the sync bundle (example): `C:\CNC\Sync`.
2. Generate a key on Windows: `ssh-keygen -t ed25519 -f C:\CNC\Sync\keys\publisher_ed25519`.
3. Copy the public key (`C:\CNC\Sync\keys\publisher_ed25519.pub`) to the Debian VM.
4. On the Debian VM, place the key at `/etc/ssh/authorized_keys/publisher` and set permissions:
   - `sudo install -d -m 0755 /etc/ssh/authorized_keys`
   - `sudo install -m 0644 /path/to/publisher_ed25519.pub /etc/ssh/authorized_keys/publisher`
5. Restart SSH: `sudo systemctl restart ssh`.
6. From Windows, test: `sftp -i C:\CNC\Sync\keys\publisher_ed25519 publisher@<ftp-vm-ip>`.

## Windows Sync (WinSCP)
1. Download WinSCP portable from `https://winscp.net/download/WinSCP-6.5.5-Portable.zip/download`.
2. Use either:
   - **Installer**: ensure `WinSCP.com` and `WinSCP.exe` are available and note the path.
   - **Portable**: extract both `WinSCP.com` and `WinSCP.exe` into the same folder as `windows/SyncCncToFtp.ps1`.
3. Determine the host key by running (first-time): `"C:\Path\To\WinSCP.com" /command "open sftp://publisher@<ftp-vm-ip>/" "exit"` and copy the reported `ssh-ed25519` host key string.
4. Place `SyncCncToFtp.ps1`, `SyncCncToFtp.cmd`, `WinSCP.com`, and `WinSCP.exe` into `C:\CNC\Sync`.
5. Create the default source directory: `C:\CNC\Jobs` (or override `-SourcePath` when running).
6. Convert the SSH key to PPK for WinSCP:
   - `C:\CNC\Sync\WinSCP.com /keygen C:\CNC\Sync\keys\publisher_ed25519 /output=C:\CNC\Sync\keys\publisher_ed25519.ppk`
7. Run the sync script from the same folder you want logs to land in:
   - `powershell.exe -File .\SyncCncToFtp.ps1 -SftpHost <ftp-vm-ip> -HostKey "ssh-ed25519 256 ..."`
   - Optional: save the host key to `C:\CNC\Sync\hostkey.txt` and omit `-HostKey`.
   - Optional override: `-WinScpPath "C:\Program Files (x86)\WinSCP\WinSCP.com"`
8. Logs are written to `SyncCncToFtp.log` in the same directory as the script.

### Schedule on Windows
1. Open Task Scheduler → Create Task.
2. **General**: run whether user is logged on or not; run with highest privileges.
3. **Triggers**: create a schedule (e.g., every 5 minutes).
4. **Actions**:
   - Program/script: `powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\CNC\Sync\SyncCncToFtp.ps1" -SftpHost <ftp-vm-ip> -HostKey "ssh-ed25519 256 ..."`
   - Optional: save the host key to `C:\CNC\Sync\hostkey.txt` and omit `-HostKey`.
   - Start in: `C:\CNC\Sync`
5. **Conditions**: disable “Start the task only if the computer is on AC power” if needed.
6. **Settings**: allow task to run on demand; stop if runs longer than expected.
7. Optional: use `windows/SyncCncToFtp.cmd` as the action target instead of `powershell.exe`.
8. Optional: import `windows/SyncCncToFtp.task.xml` and update the host/key values.

### Windows Sync Behavior
- `windows/SyncCncToFtp.ps1` uses WinSCP `synchronize remote -delete` to mirror changes and remove files missing on the Windows host.
- Use with care: deletions on `C:\CNC\Jobs` will remove files from `/cnc-files`.
