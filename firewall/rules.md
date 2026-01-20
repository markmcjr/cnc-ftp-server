# Firewall Policy Summary

## Inbound
- Allow CNC client subnet to TCP 21 (FTP control).
- Allow CNC client subnet to TCP 50000-50020 (FTP passive data).
- Allow publisher host to TCP 22 (SSH/SFTP).

## Outbound
- Default deny for all outbound connections.
- Optional: allow NTP and central syslog if required.

## Notes
- Keep passive FTP range aligned with `linux/vsftpd/vsftpd.conf`.
- Document any exceptions with justification and approval.
