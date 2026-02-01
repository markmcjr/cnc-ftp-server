#!/usr/bin/env bash
set -uo pipefail

# Setup logging
LOG_FILE="/var/log/cnc-ftp-setup.log"
ERRORS=()
WARNINGS=()

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_error() {
  local msg="[ERROR] $1"
  log "$msg"
  ERRORS+=("$1")
}

log_warn() {
  local msg="[WARN] $1"
  log "$msg"
  WARNINGS+=("$1")
}

log_success() {
  log "[OK] $1"
}

# Run a command and log result
run_step() {
  local description="$1"
  shift
  log "Running: $description"
  if "$@" >> "$LOG_FILE" 2>&1; then
    log_success "$description"
    return 0
  else
    log_error "$description failed"
    return 1
  fi
}

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== CNC FTP Server Setup Log ===" > "$LOG_FILE"
log "Setup started"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
log "Repository root: $repo_root"

# Production best practice: repository should be installed at /opt/cnc-ftp-server
RECOMMENDED_PATH="/opt/cnc-ftp-server"
if [[ "$repo_root" != "$RECOMMENDED_PATH" ]]; then
  log_warn "Repository is at '$repo_root' instead of '$RECOMMENDED_PATH'"
  echo "Warning: Repository is at '$repo_root' instead of '$RECOMMENDED_PATH'." >&2
  echo "For production systems, consider moving the repository to $RECOMMENDED_PATH" >&2
  echo "See README.md for installation instructions." >&2
  echo "" >&2
fi

config_file="${1:-$script_dir/setup.env}"
if [[ -f "$config_file" ]]; then
  log "Loading config from $config_file"
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a
else
  log "No config file found at $config_file, using interactive mode"
fi

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  echo "${value:-$default}"
}

FTP_USER="${FTP_USER:-$(prompt_default "FTP read-only user" "cnc_ro")}";
PUBLISHER_USER="${PUBLISHER_USER:-$(prompt_default "SFTP publisher user" "publisher")}";
FTP_USER_PASSWORD="${FTP_USER_PASSWORD:-}";
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-"publisher ftpadmin"}";
HOSTNAME="${HOSTNAME:-$(prompt_default "Hostname" "cnc-ftp")}";
INTERFACE_NAME="${INTERFACE_NAME:-$(prompt_default "Primary network interface" "ens18")}";
STATIC_IP_CIDR="${STATIC_IP_CIDR:-$(prompt_default "Static IP (CIDR)" "192.168.10.50/24")}";
GATEWAY="${GATEWAY:-$(prompt_default "Gateway" "192.168.10.1")}";
DNS_SERVERS="${DNS_SERVERS:-$(prompt_default "DNS servers (space-separated)" "192.168.10.2 1.1.1.1")}";
FTP_ROOT="${FTP_ROOT:-$(prompt_default "FTP root" "/srv/ftp")}";
FTP_DATA_DIR="${FTP_DATA_DIR:-$(prompt_default "FTP data directory" "/srv/ftp/cnc-files")}";
PASV_MIN_PORT="${PASV_MIN_PORT:-$(prompt_default "Passive min port" "50000")}";
PASV_MAX_PORT="${PASV_MAX_PORT:-$(prompt_default "Passive max port" "50020")}";
SSHD_SNIPPET_PATH="${SSHD_SNIPPET_PATH:-/etc/ssh/sshd_config.d/publisher.conf}";
AUTHORIZED_KEYS_DIR="${AUTHORIZED_KEYS_DIR:-/etc/ssh/authorized_keys}";
PUBLISHER_PUBLIC_KEY="${PUBLISHER_PUBLIC_KEY:-}";
VSFTPD_CONF_PATH="${VSFTPD_CONF_PATH:-/etc/vsftpd.conf}";
VSFTPD_USER_LIST_PATH="${VSFTPD_USER_LIST_PATH:-/etc/vsftpd.user_list}";
SYSCTL_CONF_PATH="${SYSCTL_CONF_PATH:-/etc/sysctl.d/99-ftp-hardening.conf}";
APPARMOR_DIR="${APPARMOR_DIR:-/etc/apparmor.d}";
INSTALL_PACKAGES="${INSTALL_PACKAGES:-yes}";
RESTART_SERVICES="${RESTART_SERVICES:-yes}";
RESTART_NETWORKING="${RESTART_NETWORKING:-no}";

log "Configuration:"
log "  FTP_USER=$FTP_USER"
log "  PUBLISHER_USER=$PUBLISHER_USER"
log "  SSH_ALLOW_USERS=$SSH_ALLOW_USERS"
log "  FTP_ROOT=$FTP_ROOT"
log "  FTP_DATA_DIR=$FTP_DATA_DIR"

# Install packages
if [[ "$INSTALL_PACKAGES" == "yes" ]]; then
  log "Installing packages..."
  if apt-get update >> "$LOG_FILE" 2>&1; then
    log_success "apt-get update"
  else
    log_error "apt-get update failed"
  fi

  if apt-get install -y vsftpd openssh-server apparmor apparmor-utils >> "$LOG_FILE" 2>&1; then
    log_success "Package installation"
  else
    log_error "Package installation failed"
  fi
else
  log "Skipping package installation (INSTALL_PACKAGES=no)"
fi

# Set hostname
if [[ -n "$HOSTNAME" ]]; then
  if run_step "Set hostname to $HOSTNAME" hostnamectl set-hostname "$HOSTNAME"; then
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
      sed -i "s/^127\\.0\\.1\\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
    else
      echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    fi
    log_success "Updated /etc/hosts"
  fi
fi

# Create directories
if run_step "Create FTP root directory" install -d -m 0755 "$FTP_ROOT"; then
  :
fi
if run_step "Create FTP data directory" install -d -m 0755 "$FTP_DATA_DIR"; then
  :
fi

# Create FTP user
if ! id "$FTP_USER" >/dev/null 2>&1; then
  if run_step "Create FTP user $FTP_USER" useradd -d "$FTP_ROOT" -s /usr/sbin/nologin "$FTP_USER"; then
    :
  fi
else
  log "User $FTP_USER already exists"
fi

# Create publisher user
if ! id "$PUBLISHER_USER" >/dev/null 2>&1; then
  if run_step "Create publisher user $PUBLISHER_USER" useradd -d "$FTP_ROOT" -s /usr/sbin/nologin "$PUBLISHER_USER"; then
    :
  fi
else
  log "User $PUBLISHER_USER already exists"
fi

# Set FTP user password
if [[ -n "$FTP_USER_PASSWORD" ]]; then
  if echo "$FTP_USER:$FTP_USER_PASSWORD" | chpasswd >> "$LOG_FILE" 2>&1; then
    log_success "Set password for $FTP_USER"
  else
    log_error "Failed to set password for $FTP_USER"
  fi
else
  log_warn "No password provided for $FTP_USER. Set manually with: passwd $FTP_USER"
fi

# Add nologin to /etc/shells (required for PAM/vsftpd)
if ! grep -qx "/usr/sbin/nologin" /etc/shells; then
  if echo "/usr/sbin/nologin" >> /etc/shells; then
    log_success "Added /usr/sbin/nologin to /etc/shells"
  else
    log_error "Failed to add /usr/sbin/nologin to /etc/shells"
  fi
else
  log "/usr/sbin/nologin already in /etc/shells"
fi

# Set directory permissions
if run_step "Set FTP root permissions" chmod 0755 "$FTP_ROOT"; then
  :
fi
if run_step "Set FTP root ownership" chown root:root "$FTP_ROOT"; then
  :
fi
if run_step "Set FTP data directory ownership" chown -R "$PUBLISHER_USER":"$PUBLISHER_USER" "$FTP_DATA_DIR"; then
  :
fi

# Configure vsftpd
vsftpd_template="$repo_root/linux/vsftpd/vsftpd.conf"
if [[ -f "$vsftpd_template" ]]; then
  if sed \
    -e "s/^pasv_min_port=.*/pasv_min_port=$PASV_MIN_PORT/" \
    -e "s/^pasv_max_port=.*/pasv_max_port=$PASV_MAX_PORT/" \
    "$vsftpd_template" > "$VSFTPD_CONF_PATH"; then
    log_success "Generated vsftpd.conf"
  else
    log_error "Failed to generate vsftpd.conf"
  fi
else
  log_error "vsftpd template not found at $vsftpd_template"
fi

# Create vsftpd log files
if touch /var/log/xferlog /var/log/vsftpd.log && chmod 600 /var/log/xferlog /var/log/vsftpd.log; then
  log_success "Created vsftpd log files"
else
  log_error "Failed to create vsftpd log files"
fi

# Copy vsftpd user list
if [[ -f "$repo_root/linux/vsftpd/vsftpd.user_list" ]]; then
  if cp "$repo_root/linux/vsftpd/vsftpd.user_list" "$VSFTPD_USER_LIST_PATH"; then
    log_success "Copied vsftpd.user_list"
  else
    log_error "Failed to copy vsftpd.user_list"
  fi
else
  log_error "vsftpd.user_list not found"
fi

# Configure SSH for publisher
if [[ -f "$repo_root/linux/ssh/sshd_config.publisher.conf" ]]; then
  if cp "$repo_root/linux/ssh/sshd_config.publisher.conf" "$SSHD_SNIPPET_PATH" && \
     sed -i "s/^Match User .*/Match User $PUBLISHER_USER/" "$SSHD_SNIPPET_PATH"; then
    log_success "Configured SSH for publisher user"
  else
    log_error "Failed to configure SSH for publisher"
  fi
else
  log_error "sshd_config.publisher.conf not found"
fi

# Configure SSH AllowUsers and AuthorizedKeysFile
if cat > /etc/ssh/sshd_config.d/10-allow-users.conf <<EOF
AllowUsers $SSH_ALLOW_USERS
AuthorizedKeysFile /etc/ssh/authorized_keys/%u
EOF
then
  log_success "Configured SSH AllowUsers: $SSH_ALLOW_USERS"
else
  log_error "Failed to configure SSH AllowUsers"
fi

# Create authorized keys directory
if run_step "Create authorized keys directory" install -d -m 0755 "$AUTHORIZED_KEYS_DIR"; then
  :
fi

# Install publisher public key if provided
if [[ -n "$PUBLISHER_PUBLIC_KEY" ]]; then
  if echo "$PUBLISHER_PUBLIC_KEY" > "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER" && \
     chmod 0644 "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER" && \
     chown root:root "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER"; then
    log_success "Installed publisher public key"
  else
    log_error "Failed to install publisher public key"
  fi
else
  log_warn "No publisher key provided. Place the public key at $AUTHORIZED_KEYS_DIR/$PUBLISHER_USER"
fi

# Copy sysctl config
if [[ -f "$repo_root/linux/sysctl/99-ftp-hardening.conf" ]]; then
  if cp "$repo_root/linux/sysctl/99-ftp-hardening.conf" "$SYSCTL_CONF_PATH"; then
    log_success "Copied sysctl hardening config"
  else
    log_error "Failed to copy sysctl config"
  fi
else
  log_error "sysctl config not found"
fi

# Copy and load AppArmor profiles
if [[ -f "$repo_root/linux/apparmor/usr.sbin.vsftpd" ]]; then
  if cp "$repo_root/linux/apparmor/usr.sbin.vsftpd" "$APPARMOR_DIR/usr.sbin.vsftpd"; then
    log_success "Copied vsftpd AppArmor profile"
  else
    log_error "Failed to copy vsftpd AppArmor profile"
  fi
else
  log_error "vsftpd AppArmor profile not found"
fi

if [[ -f "$repo_root/linux/apparmor/usr.lib.openssh.sftp-server" ]]; then
  if cp "$repo_root/linux/apparmor/usr.lib.openssh.sftp-server" "$APPARMOR_DIR/usr.lib.openssh.sftp-server"; then
    log_success "Copied sftp-server AppArmor profile"
  else
    log_error "Failed to copy sftp-server AppArmor profile"
  fi
else
  log_error "sftp-server AppArmor profile not found"
fi

# Load AppArmor profiles
if run_step "Load vsftpd AppArmor profile" apparmor_parser -r "$APPARMOR_DIR/usr.sbin.vsftpd"; then
  :
fi
if run_step "Load sftp-server AppArmor profile" apparmor_parser -r "$APPARMOR_DIR/usr.lib.openssh.sftp-server"; then
  :
fi

# Apply sysctl settings
if sysctl --system >> "$LOG_FILE" 2>&1; then
  log_success "Applied sysctl settings"
else
  log_error "Failed to apply sysctl settings"
fi

# Configure static network if specified
if [[ -n "$STATIC_IP_CIDR" && -n "$INTERFACE_NAME" ]]; then
  log "Configuring static network..."
  if cat > /etc/systemd/network/10-ftp-static.network <<EOF
[Match]
Name=$INTERFACE_NAME

[Network]
Address=$STATIC_IP_CIDR
Gateway=$GATEWAY
DNS=$DNS_SERVERS
EOF
  then
    log_success "Created network config for $INTERFACE_NAME"
  else
    log_error "Failed to create network config"
  fi

  systemctl enable systemd-networkd >> "$LOG_FILE" 2>&1
  if systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
    systemctl enable systemd-resolved >> "$LOG_FILE" 2>&1
  else
    log_warn "systemd-resolved not found. Configure /etc/resolv.conf manually."
  fi

  if [[ "$RESTART_NETWORKING" == "yes" ]]; then
    if run_step "Restart networking" systemctl restart systemd-networkd; then
      :
    fi
    if systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
      systemctl restart systemd-resolved >> "$LOG_FILE" 2>&1
    fi
  else
    log "Static network config written. Restart networking to apply."
  fi
fi

# Restart services
if [[ "$RESTART_SERVICES" == "yes" ]]; then
  if run_step "Restart vsftpd" systemctl restart vsftpd; then
    :
  fi
  if run_step "Restart SSH" systemctl restart ssh; then
    :
  fi
fi

# Print summary
echo ""
echo "=============================================="
log "Setup completed"
echo "=============================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "ERRORS (${#ERRORS[@]}):"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo ""
  echo "WARNINGS (${#WARNINGS[@]}):"
  for warn in "${WARNINGS[@]}"; do
    echo "  - $warn"
  done
fi

echo ""
if [[ ${#ERRORS[@]} -eq 0 ]]; then
  echo "STATUS: SUCCESS"
  echo ""
  echo "Next steps:"
  echo "  1. Set password for $FTP_USER: passwd $FTP_USER"
  echo "  2. Verify SSH keys are in place at $AUTHORIZED_KEYS_DIR/"
  echo "  3. Apply firewall rules from firewall/rules.md"
  echo "  4. Test FTP: ftp <server-ip> (login as $FTP_USER)"
  echo "  5. Test SFTP: sftp -i <key> $PUBLISHER_USER@<server-ip>"
else
  echo "STATUS: COMPLETED WITH ERRORS"
  echo "Review the log file: $LOG_FILE"
fi

echo ""
echo "Log file: $LOG_FILE"
