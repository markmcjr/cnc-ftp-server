# Manual Setup Guide

Follow these steps to configure the Debian FTP VM and the Windows publisher without running the setup scripts.

## 1) Prepare Debian
1. Create the VM with: 80 GB disk, 1 vCPU, 1 GB RAM.
2. Install Debian 12 (netinst ISO): `https://get.debian.org/images/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso`.
3. Set the hostname: `sudo hostnamectl set-hostname cnc-ftp`.
4. Update `/etc/hosts` so sudo resolves the new hostname:
   - `sudoedit /etc/hosts`
   - Set the line to: `127.0.1.1 cnc-ftp` (optionally add the old name as an alias).
5. Configure a static IP (systemd-networkd):
   - Identify the NIC: `ip -br link` (example: `ens18`).
   - Create `/etc/systemd/network/10-ftp-static.network` with:
     ```
     [Match]
     Name=ens18

     [Network]
     Address=192.168.10.50/24
     Gateway=192.168.10.1
     DNS=192.168.10.2 1.1.1.1
     ```
   - Enable and restart networking:
     - `sudo systemctl enable systemd-networkd`
     - If `systemd-resolved` exists: `sudo systemctl enable systemd-resolved` and `sudo systemctl restart systemd-resolved`
     - Otherwise, set DNS manually in `/etc/resolv.conf`.
     - `sudo systemctl restart systemd-networkd`
6. Install packages: `sudo apt-get update && sudo apt-get install -y vsftpd openssh-server apparmor apparmor-utils`.
7. Create directories:
   - `sudo install -d -m 0755 /srv/ftp`
   - `sudo install -d -m 0755 /srv/ftp/cnc-files`

## 2) Create Users
1. Create FTP read-only user: `sudo useradd -d /srv/ftp -s /usr/sbin/nologin cnc_ro`.
2. Set the FTP password: `sudo passwd cnc_ro`.
3. Ensure `/usr/sbin/nologin` is allowed for FTP:
   - `echo /usr/sbin/nologin | sudo tee -a /etc/shells`
4. Create publisher user: `sudo useradd -d /srv/ftp -s /usr/sbin/nologin publisher`.
5. Ensure chroot root is owned by root:
   - `sudo chown root:root /srv/ftp`
   - `sudo chmod 0755 /srv/ftp`
6. Give publisher ownership of data directory:
   - `sudo chown -R publisher:publisher /srv/ftp/cnc-files`

## 3) Configure vsftpd
1. Copy the template: `sudo cp linux/vsftpd/vsftpd.conf /etc/vsftpd.conf`.
2. Copy user allowlist: `sudo cp linux/vsftpd/vsftpd.user_list /etc/vsftpd.user_list`.
3. Restart: `sudo systemctl restart vsftpd`.

## 4) Configure SSH/SFTP
1. Copy snippet: `sudo cp linux/ssh/sshd_config.publisher.conf /etc/ssh/sshd_config.d/publisher.conf`.
2. Restrict SSH users: create `/etc/ssh/sshd_config.d/10-allow-users.conf` with:
   ```
   AllowUsers publisher helpdesk
   ```
3. Add the publisher’s public key:
   - `sudo install -d -m 0755 /etc/ssh/authorized_keys`
   - `sudo install -m 0644 /path/to/publisher_ed25519.pub /etc/ssh/authorized_keys/publisher`
4. Restart SSH: `sudo systemctl restart ssh`.

## 5) Apply Sysctl Hardening
1. Copy settings: `sudo cp linux/sysctl/99-ftp-hardening.conf /etc/sysctl.d/99-ftp-hardening.conf`.
2. Apply: `sudo sysctl --system`.

## 6) Apply AppArmor Profiles
1. Copy profiles:
   - `sudo cp linux/apparmor/usr.sbin.vsftpd /etc/apparmor.d/usr.sbin.vsftpd`
   - `sudo cp linux/apparmor/usr.lib.openssh.sftp-server /etc/apparmor.d/usr.lib.openssh.sftp-server`
2. Load:
   - `sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.vsftpd`
   - `sudo apparmor_parser -r /etc/apparmor.d/usr.lib.openssh.sftp-server`

## 7) Windows Publisher Setup
1. Create folder: `C:\CNC\Sync`.
2. Generate key on Windows:
   - Create: `C:\CNC\Sync\keys`
   - Run: `ssh-keygen -t ed25519 -f C:\CNC\Sync\keys\publisher_ed25519`
3. Convert the key to WinSCP/PPK format:
   - `C:\CNC\Sync\WinSCP.com /keygen C:\CNC\Sync\keys\publisher_ed25519 /output=C:\CNC\Sync\keys\publisher_ed25519.ppk`
4. Copy the public key to Debian:
   - Open `C:\CNC\Sync\keys\publisher_ed25519.pub` and copy the single line.
   - On Debian: `sudo install -d -m 0755 /etc/ssh/authorized_keys`
   - Paste to: `sudo tee /etc/ssh/authorized_keys/publisher >/dev/null` then Ctrl+D.
   - `sudo chmod 0644 /etc/ssh/authorized_keys/publisher && sudo chown root:root /etc/ssh/authorized_keys/publisher`
5. Create `SyncCncToFtp.ps1` and `SyncCncToFtp.cmd` in `C:\CNC\Sync` (paste content from this guide or the repo).
6. Create a source folder for CNC jobs (default used by the script): `C:\CNC\Jobs`.
7. Download WinSCP portable from `https://winscp.net/download/WinSCP-6.5.5-Portable.zip/download` and place both `WinSCP.com` and `WinSCP.exe` in `C:\CNC\Sync`.
8. Determine host key:
   - `C:\CNC\Sync\WinSCP.com /command "open sftp://publisher@<ftp-vm-ip>/" "exit"`
   - Copy the reported `ssh-ed25519 255 ...` host key string and paste it into `SyncCncToFtp.cmd` as the `-HostKey` value (no trailing punctuation).
9. If the host key is truncated when running the `.cmd`, run the PowerShell script directly:
   - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\CNC\Sync\SyncCncToFtp.ps1 -SftpHost <ftp-vm-ip> -HostKey "ssh-ed25519 255 ..."`
10. Optional: save the host key to `C:\CNC\Sync\hostkey.txt` and omit `-HostKey`.
11. Sync behavior: the script mirrors `C:\CNC\Jobs` to `/cnc-files` and deletes remote files that no longer exist locally.

## 8) Firewall
Apply the inbound/outbound policy in `firewall/rules.md` on the upstream firewall.

When you’re ready, use `docs/test-guide.md` to validate the setup and then test the scripts.
