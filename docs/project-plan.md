# Internal CNC FTP Server — Project Plan & Build Guide

## 1. Purpose & Scope
Provide a **simple, secure, internal FTP service** for CNC machines to **pull** machine instruction files. Security priority is **preventing lateral movement** if the FTP server is compromised. Data confidentiality is **not** a concern.

**In scope**
- Plain FTP (read-only) for CNC clients
- SSH/SFTP for publishing from Windows
- Debian-based minimal VM
- DMZ placement with strict firewalling

**Out of scope**
- SFTP for CNC clients
- Encryption of CNC data in transit
- Complex HA or clustering

---

## 2. Final Architecture (Locked)

### Network Topology
- **Single NIC** VM in a **DMZ subnet**
- Upstream firewall handles all routing
- FTP VM is not a router and cannot pivot

### Traffic Flows
- CNC Clients → FTP VM: **FTP (TCP 21 + passive range)**
- Windows Publisher → FTP VM: **SSH/SFTP (TCP 22)**
- FTP VM → Anywhere: **Denied (default)**

---

## 3. Threat Model Summary

### Accepted Risks
- FTP credentials and data may be sniffed internally
- CNC files are non-sensitive

### Mitigated Risks
- Lateral movement into internal network
- Pivoting via routing or dual-homing
- Filesystem escape or command execution

---

## 4. OS & Platform Choices

- **OS**: Debian 12 (Bookworm)
- **Install profile**: Minimal + *standard system utilities only*
- **Disk**: 8 GB total
- **NICs**: 1 (DMZ only)

Rationale: stability, predictability, minimal attack surface, long support window.

---

## 5. Host Hardening (Kernel & OS)

### Sysctl Hardening
- Disable IPv4/IPv6 forwarding
- Enable reverse-path filtering
- Disable ICMP redirects
- Enable TCP SYN cookies

### Filesystem Hardening
- Separate filesystem for `/srv/ftp`
- Mount options: `nodev,nosuid,noexec`

---

## 6. Services & Users

### Services
- vsftpd (FTP)
- OpenSSH (SFTP publishing)
- UFW firewall
- AppArmor (enforcing)

### Users
- `cnc_ro`: FTP-only, read-only, chrooted
- `publisher`: SFTP-only, key-based, chrooted, no shell

---

## 7. Directory Layout

```
/srv/ftp/
└── cnc-files/
    ├── job1.nc
    ├── job2.nc
```

---

## 8. FTP Configuration (vsftpd)

- No anonymous access
- Chroot enabled
- Uploads/deletes disabled
- Passive mode only
- Fixed passive port range
- User allowlist
- Logging enabled

---

## 9. SSH / SFTP Configuration

- Password auth disabled
- Publisher-only access
- Forced internal-sftp
- No forwarding
- Chroot enforced

---

## 10. Firewall Policy

### Inbound
- CNC IPs → TCP 21
- CNC IPs → TCP 50000–50020
- Publisher IP → TCP 22

### Outbound
- Default deny
- Optional NTP/syslog only

---

## 11. Windows Publishing Workflow

- Scheduled task every 2–5 minutes
- robocopy from share
- sftp push to FTP VM
- Key-based auth

---

## 12. Operations & Validation

- Validate listening ports
- Validate permissions
- Central logging (optional)

---

## 13. Security Posture Summary

If compromised:
- No lateral movement
- No pivoting
- No outbound access
- Low-value data only

---

## 14. Enhancements Included in the Design (Locked)

- AppArmor tuning for vsftpd and internal-sftp
- File integrity monitoring on `/srv/ftp/cnc-files`
- Health-check / canary file
- Automated rebuild / image-based redeploy

---

## 15. Build Status

- Architecture: Locked
- OS choice: Locked
- Security model: Locked
