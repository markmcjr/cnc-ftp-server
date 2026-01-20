# Setup Status

Use this file to track progress and resume later.

## Completed
- Debian VM created (80 GB disk, 1 vCPU, 1 GB RAM) and Debian 12 installed.
- Hostname set to `cnc-ftp` and `/etc/hosts` updated.
- Static IP configured with systemd-networkd on `ens33`.
- vsftpd and OpenSSH installed and running.
- FTP read-only login for `cnc_ro` verified (uploads/deletes denied).
- SFTP access for `publisher` verified.
- AppArmor and sysctl hardening applied.
- WinSCP portable downloaded; `WinSCP.com` and `WinSCP.exe` placed in `C:\CNC\Sync`.
- Windows key generated and converted to PPK; publisher public key installed on Debian.
- WinSCP sync succeeded and files arrived under `/srv/ftp/cnc-files`.
- Task Scheduler configured to run WinSCP sync every 5 minutes.

## Pending / Optional
- Apply upstream firewall rules in `firewall/rules.md` (skipped for testing).
- Run delete-mirroring test (remove a file in `C:\CNC\Jobs`, re-sync, verify removal on Debian).

## Notes
- WinSCP uses `publisher_ed25519.ppk`.
- Host key stored in `C:\CNC\Sync\hostkey.txt`.
