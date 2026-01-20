# Step-by-Step Test Guide

Follow each step in order. After completing a step, confirm the expected result before moving on.

## 1) Validate Services on Debian
1. Run: `systemctl status vsftpd`.
   - Expected: service is active (running).
2. Run: `systemctl status ssh`.
   - Expected: service is active (running).
3. Run: `ss -lntp | grep -E ':(21|22|50000|50020)'`.
   - Expected: FTP (21) and SSH (22) listening; passive range handled by firewall.

Pause here and confirm service status.

## 2) Verify FTP Read-Only Access
1. From a CNC client or test machine, connect using FTP as `cnc_ro`.
2. List files in `/cnc-files`.
   - Expected: files are visible.
3. Attempt to upload or delete a file.
   - Expected: operation is denied.

Pause here and confirm read-only behavior.

## 3) Validate SFTP Publisher Access (Windows)
1. From Windows, test SFTP: `sftp -i C:\CNC\Sync\keys\publisher_ed25519 publisher@<ftp-vm-ip>`.
   - Expected: login succeeds and you land in `/` (chroot).
2. Run: `pwd` and `ls`.
   - Expected: `/` and `cnc-files` directory visible.

Pause here and confirm SFTP access.

## 4) Test WinSCP Sync Script
1. Place `WinSCP.com`, `WinSCP.exe`, `SyncCncToFtp.ps1`, and `SyncCncToFtp.cmd` in `C:\CNC\Sync`.
2. Ensure the default source directory exists: `C:\CNC\Jobs` (create and add a test file if needed).
3. Convert the SSH key to PPK for WinSCP:
   - `C:\CNC\Sync\WinSCP.com /keygen C:\CNC\Sync\keys\publisher_ed25519 /output=C:\CNC\Sync\keys\publisher_ed25519.ppk`
4. Run from PowerShell: `powershell.exe -File .\SyncCncToFtp.ps1 -SftpHost <ftp-vm-ip> -HostKey "ssh-ed25519 255 ..."`.
   - Optional: save the host key to `C:\CNC\Sync\hostkey.txt` and omit `-HostKey`.
   - Expected: `SyncCncToFtp.log` created in `C:\CNC\Sync`.
5. Check `SyncCncToFtp.log` for successful sync messages.
6. Confirm delete mirroring: remove a file from `C:\CNC\Jobs`, rerun the sync, and verify it is removed from `/srv/ftp/cnc-files`.

Pause here and confirm sync output.

## 5) Confirm Files on Debian
1. On Debian, run: `ls -l /srv/ftp/cnc-files`.
   - Expected: new or updated files present, owned by the publisher user.
2. Optional: run `bash linux/scripts/fim-check.sh`.
   - Expected: checksum validation succeeds (if manifest is configured).

Pause here and confirm file presence.

## 6) Firewall Validation (Optional)
1. From a non-allowed host, attempt to connect to port 21 and 22.
   - Expected: connection blocked.
2. From allowed CNC client IPs, verify port 21 and passive range access.

Pause here and confirm firewall behavior.
