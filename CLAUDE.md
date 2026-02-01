# CNC FTP Server - Project Context

## Overview
Internal FTP server for CNC machines. Debian 12 (Bookworm) minimal install hosted on a VM.

## Architecture
- **FTP (port 21)**: Read-only access for CNC machines using `cnc_ro` user with password auth
- **SFTP (port 22)**: Write access for Windows publisher workstation using `publisher` user with SSH key auth
- **SSH admin**: `ftpadmin` user for server administration

## Key Paths
- Production install location: `/opt/cnc-ftp-server/`
- FTP root: `/srv/ftp/` (owned by root, not writable)
- FTP data directory: `/srv/ftp/cnc-files/` (owned by publisher)
- SSH authorized keys: `/etc/ssh/authorized_keys/%u`
- vsftpd config: `/etc/vsftpd.conf`
- AppArmor profiles: `/etc/apparmor.d/`

## Important Files
- `linux/scripts/setup-ftp.sh` - Main setup script (run as root with `su -`)
- `linux/scripts/setup.env.example` - Configuration template
- `linux/apparmor/usr.sbin.vsftpd` - vsftpd AppArmor profile
- `linux/ssh/sshd_config.publisher.conf` - SFTP chroot config for publisher
- `windows/SyncCncToFtp.ps1` - Windows sync script using WinSCP

## Common Issues & Solutions

### vsftpd "setgroups" or capability errors
The AppArmor profile needs these capabilities:
```
capability net_bind_service,
capability setgid,
capability setuid,
capability sys_chroot,
capability chown,
```
Reload with: `apparmor_parser -r /etc/apparmor.d/usr.sbin.vsftpd`

### vsftpd "failed to open xferlog"
Log files must exist before vsftpd starts:
```bash
touch /var/log/xferlog /var/log/vsftpd.log
chmod 600 /var/log/xferlog /var/log/vsftpd.log
```
AppArmor profile needs: `/var/log/xferlog rw,`

### SSH prompting for password instead of using key
Ensure global AuthorizedKeysFile is set in `/etc/ssh/sshd_config.d/10-allow-users.conf`:
```
AllowUsers publisher ftpadmin
AuthorizedKeysFile /etc/ssh/authorized_keys/%u
```

### SSH_ALLOW_USERS parsing error
Values with spaces in setup.env must be quoted:
```
SSH_ALLOW_USERS="publisher ftpadmin"
DNS_SERVERS="192.168.10.2 1.1.1.1"
```

### git "dubious ownership" error
Set proper ownership: `chown -R ftpadmin:ftpadmin /opt/cnc-ftp-server`

## Testing Commands

### Test FTP (from Windows):
```
ftp <vm-ip>
# Login: cnc_ro / <password>
# Commands: ls, get <filename>, quit
```

### Test SFTP publisher access:
```powershell
scp -i C:\CNC\Sync\keys\publisher_ed25519 C:\CNC\Jobs\test.txt publisher@<vm-ip>:/cnc-files/
```

### Test ftpadmin SSH:
```powershell
ssh -i C:\CNC\Sync\keys\ftpadmin_ed25519 ftpadmin@<vm-ip>
```

## Notes
- Debian 12 minimal does not include `sudo` - use `su -` instead
- CNC machines only support FTP (not SFTP) - this is why vsftpd is used
- Setup script restricts SSH via AllowUsers - install keys BEFORE running setup
