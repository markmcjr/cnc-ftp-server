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

### Access Methods
This server provides two separate access methods:
- **FTP (port 21)**: Read-only access for CNC machines and clients that only support FTP (not SFTP). Uses the `cnc_ro` user with password authentication.
- **SFTP (port 22)**: Write access for the publisher workstation to upload files. Uses the `publisher` user with SSH key authentication.

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

> **Note**: Debian 12 minimal does not include `sudo` by default. The instructions below use `su -` to run commands as root. If you prefer sudo, install it first: `su -c "apt install -y sudo"` then add your user to the sudo group: `su -c "usermod -aG sudo <username>"` (log out and back in to apply).

### Recommended Installation Path
For production systems, install the repository to `/opt/cnc-ftp-server/`:
```bash
# Become root
su -

# Create directory and set ownership
mkdir -p /opt/cnc-ftp-server
chown <your-username>:<your-username> /opt/cnc-ftp-server
exit
```

This follows the [Filesystem Hierarchy Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s13.html) for add-on application packages.

### Getting the Repository onto the VM
Choose one of the following methods to place the repository at `/opt/cnc-ftp-server/`:

**Option A: SSH server installed during Debian setup (recommended)**
```bash
# From your workstation (requires root SSH or pre-created /opt/cnc-ftp-server):
scp -r cnc-ftp-server/ user@<vm-ip>:~/
# Then on the VM:
su -
mv /home/<username>/cnc-ftp-server /opt/
exit

# Or clone directly on the VM as root:
su -
git clone <repo-url> /opt/cnc-ftp-server
exit
```

**Option B: No SSH server yet (manual transfer)**
- **USB drive**: Copy the repo to a USB drive, mount it on the VM, and copy to `/opt/`:
  ```bash
  su -
  mount /dev/sdb1 /mnt
  cp -r /mnt/cnc-ftp-server /opt/
  umount /mnt
  exit
  ```
- **Shared folder (VMware/VirtualBox)**: Configure a shared folder in your hypervisor:
  ```bash
  su -
  cp -r /mnt/hgfs/cnc-ftp-server /opt/
  exit
  ```

**Option C: GitHub without SSH**
```bash
# Log into the VM console directly and become root
su -
apt update && apt install -y git
git clone https://github.com/<org>/cnc-ftp-server.git /opt/cnc-ftp-server
exit
```

**After copying/cloning**: Set ownership so ftpadmin can manage the repo (e.g., `git pull`):
```bash
su -
chown -R ftpadmin:ftpadmin /opt/cnc-ftp-server
exit
```

### Pre-Setup: Create Admin User and Prepare SSH Keys

> **Important**: The setup script configures SSH `AllowUsers` which restricts SSH access to specific users. Create your admin user and prepare SSH keys BEFORE running the setup script to avoid being locked out.

**Step 1: Create the ftpadmin user on the Debian VM:**
```bash
su -
useradd -m -s /bin/bash ftpadmin
passwd ftpadmin
exit
```

**Step 2: Generate SSH keys on Windows (publisher workstation):**
```powershell
# Create folders
mkdir C:\CNC\Sync\keys

# Generate publisher key (for automated sync)
ssh-keygen -t ed25519 -f C:\CNC\Sync\keys\publisher_ed25519

# Generate ftpadmin key (for admin access)
ssh-keygen -t ed25519 -f C:\CNC\Sync\keys\ftpadmin_ed25519
```

**Step 3: Copy public keys to the Debian VM:**
```powershell
# Copy keys via scp (if SSH server was installed during Debian setup)
scp C:\CNC\Sync\keys\publisher_ed25519.pub ftpadmin@<vm-ip>:~/
scp C:\CNC\Sync\keys\ftpadmin_ed25519.pub ftpadmin@<vm-ip>:~/
```
If SSH is not yet available, copy the `.pub` files via USB or paste their contents manually.

**Step 4: Install the keys on the Debian VM (as root):**
```bash
su -
install -d -m 0755 /etc/ssh/authorized_keys

# Install publisher key
install -m 0644 /home/ftpadmin/publisher_ed25519.pub /etc/ssh/authorized_keys/publisher

# Install ftpadmin key
install -m 0644 /home/ftpadmin/ftpadmin_ed25519.pub /etc/ssh/authorized_keys/ftpadmin

# Clean up
rm /home/ftpadmin/*.pub
exit
```

**Step 5: Test SSH connection from Windows before proceeding:**
```powershell
# Test ftpadmin access (should connect without password prompt)
ssh -i C:\CNC\Sync\keys\ftpadmin_ed25519 ftpadmin@<vm-ip> "echo 'ftpadmin key works'"
```
> **Important**: This must succeed before running the setup script. If it fails, verify the key was installed correctly and has proper permissions (0644). The `publisher` user will be created by the setup script, so test that connection after setup completes.

### Setup Steps
1. Ensure the repo is at `/opt/cnc-ftp-server/` using one of the methods above.
2. **Ensure SSH keys are in place** (see Pre-Setup above) — the setup script will restrict SSH access.
3. Review `linux/scripts/setup.env.example` and save as `linux/scripts/setup.env` if you want non-interactive setup.
4. Run the setup script as root:
   ```bash
   su -
   bash /opt/cnc-ftp-server/linux/scripts/setup-ftp.sh
   ```
5. Apply the firewall policy described in `firewall/rules.md` on the upstream firewall.

### Non-Interactive Setup
```bash
su -
bash /opt/cnc-ftp-server/linux/scripts/setup-ftp.sh /opt/cnc-ftp-server/linux/scripts/setup.env
```
- Set `INSTALL_PACKAGES=no` in the env file if you want to install packages manually.

### Validation
- Review the setup log: `cat /var/log/cnc-ftp-setup.log`
- Check `systemctl status vsftpd` and `systemctl status ssh`.
- Confirm passive ports and user allowlist match `linux/vsftpd/vsftpd.conf` and `linux/vsftpd/vsftpd.user_list`.

**Test FTP access (CNC clients use FTP, not SFTP):**
```powershell
ftp <ftp-vm-ip>
# Login: cnc_ro / <password>
# Commands: ls, get <filename>, quit
```

**Test SFTP/SCP access (publisher upload):**
```powershell
# Quick test - copy a file to the server
scp -i C:\CNC\Sync\keys\publisher_ed25519 C:\CNC\Jobs\test.txt publisher@<ftp-vm-ip>:/cnc-files/
```

## Windows Sync Setup

### Prerequisites
1. SSH keys generated and installed (see Pre-Setup above)
2. FTP server running and accessible
3. Server repository is up to date (`git pull` on the server if needed)

### Quick Install (Recommended)

**Step 1: Create the sync folder and download the installer:**
```powershell
# Create folder structure (this should already exist from previous steps)
mkdir C:\CNC\Sync

# Copy installer from server (requires ftpadmin SSH access)
scp -i C:\CNC\Sync\keys\ftpadmin_ed25519 ftpadmin@<ftp-vm-ip>:/opt/cnc-ftp-server/windows/Install-CncSync.ps1 C:\CNC\Sync\
```

> **Note: SSH Key Permissions on Windows**
> If you get "WARNING: UNPROTECTED PRIVATE KEY FILE!", fix permissions:
> ```powershell
> icacls C:\CNC\Sync\keys\ftpadmin_ed25519 /inheritance:r /grant:r "$($env:USERNAME):(R)"
> icacls C:\CNC\Sync\keys\publisher_ed25519 /inheritance:r /grant:r "$($env:USERNAME):(R)"
> ```

> The installer will automatically download the other required files (`SyncCncToFtp.ps1`, etc.) from the server.

**Step 2: Download WinSCP portable:**
- Download from: `https://winscp.net/download/WinSCP-6.5.5-Portable.zip`
- Extract `WinSCP.com` and `WinSCP.exe` to `C:\CNC\Sync\`

**Step 3: Run the installer:**
```powershell
cd C:\CNC\Sync
powershell -ExecutionPolicy Bypass -File .\Install-CncSync.ps1
```

The installer will:
- Download required sync scripts from the server automatically
- Prompt for server IP, sync folder, and schedule interval
- Auto-detect or prompt for the SSH host key
- Convert your SSH key to PPK format (required by WinSCP)
- Create a Windows scheduled task for automated sync

### Updating Settings

Edit `C:\CNC\Sync\sync-config.ps1` and re-run the installer:
```powershell
cd C:\CNC\Sync
powershell -ExecutionPolicy Bypass -File .\Install-CncSync.ps1 -ConfigOnly
```

### Removing the Scheduled Task
```powershell
cd C:\CNC\Sync
powershell -ExecutionPolicy Bypass -File .\Install-CncSync.ps1 -Uninstall
```

### Manual Sync Test
```powershell
cd C:\CNC\Sync
.\SyncCncToFtp.ps1 -SftpHost <ftp-vm-ip> -HostKey "ssh-ed25519 256 ..."
```

### Configuration File Reference

The `sync-config.ps1` file contains all settings:
| Setting | Description | Default |
|---------|-------------|---------|
| `SftpHost` | FTP server IP/hostname | (required) |
| `HostKey` | SSH host key for verification | (auto-detected) |
| `SourcePath` | Local folder to sync | `C:\CNC\Jobs` |
| `RemotePath` | Remote folder on server | `/cnc-files` |
| `SshKeyPath` | Path to publisher SSH key (PPK) | `C:\CNC\Sync\keys\publisher_ed25519.ppk` |
| `EnableSchedule` | Enable/disable scheduled sync | `$true` |
| `SyncIntervalMinutes` | How often to sync (minutes) | `5` |

### Windows Sync Behavior
- Uses WinSCP `synchronize remote -delete` to mirror changes
- Files deleted from `C:\CNC\Jobs` will be removed from `/cnc-files`
- Logs written to `C:\CNC\Sync\SyncCncToFtp.log`
