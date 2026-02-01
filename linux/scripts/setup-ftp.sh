#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

# Production best practice: repository should be installed at /opt/cnc-ftp-server
RECOMMENDED_PATH="/opt/cnc-ftp-server"
if [[ "$repo_root" != "$RECOMMENDED_PATH" ]]; then
  echo "Warning: Repository is at '$repo_root' instead of '$RECOMMENDED_PATH'." >&2
  echo "For production systems, consider moving the repository to $RECOMMENDED_PATH" >&2
  echo "See README.md for installation instructions." >&2
  echo "" >&2
fi

config_file="${1:-$script_dir/setup.env}"
if [[ -f "$config_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a
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
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-"publisher helpdesk"}";
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

if [[ "$INSTALL_PACKAGES" == "yes" ]]; then
  apt-get update
  apt-get install -y vsftpd openssh-server apparmor apparmor-utils
fi

if [[ -n "$HOSTNAME" ]]; then
  hostnamectl set-hostname "$HOSTNAME"
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\\.0\\.1\\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
  else
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
  fi
fi

install -d -m 0755 "$FTP_ROOT"
install -d -m 0755 "$FTP_DATA_DIR"

if ! id "$FTP_USER" >/dev/null 2>&1; then
  useradd -d "$FTP_ROOT" -s /usr/sbin/nologin "$FTP_USER"
fi

if ! id "$PUBLISHER_USER" >/dev/null 2>&1; then
  useradd -d "$FTP_ROOT" -s /usr/sbin/nologin "$PUBLISHER_USER"
fi

if [[ -n "$FTP_USER_PASSWORD" ]]; then
  echo "$FTP_USER:$FTP_USER_PASSWORD" | chpasswd
else
  echo "Set a password for $FTP_USER with: passwd $FTP_USER" >&2
fi

if ! grep -qx "/usr/sbin/nologin" /etc/shells; then
  echo "/usr/sbin/nologin" >> /etc/shells
fi

chmod 0755 "$FTP_ROOT"
chown root:root "$FTP_ROOT"
chown -R "$PUBLISHER_USER":"$PUBLISHER_USER" "$FTP_DATA_DIR"

vsftpd_template="$repo_root/linux/vsftpd/vsftpd.conf"
sed \
  -e "s/^pasv_min_port=.*/pasv_min_port=$PASV_MIN_PORT/" \
  -e "s/^pasv_max_port=.*/pasv_max_port=$PASV_MAX_PORT/" \
  "$vsftpd_template" > "$VSFTPD_CONF_PATH"

cp "$repo_root/linux/vsftpd/vsftpd.user_list" "$VSFTPD_USER_LIST_PATH"

cp "$repo_root/linux/ssh/sshd_config.publisher.conf" "$SSHD_SNIPPET_PATH"
sed -i "s/^Match User .*/Match User $PUBLISHER_USER/" "$SSHD_SNIPPET_PATH"

cat > /etc/ssh/sshd_config.d/10-allow-users.conf <<EOF
AllowUsers $SSH_ALLOW_USERS
EOF

install -d -m 0755 "$AUTHORIZED_KEYS_DIR"

if [[ -n "$PUBLISHER_PUBLIC_KEY" ]]; then
  echo "$PUBLISHER_PUBLIC_KEY" > "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER"
  chmod 0644 "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER"
  chown root:root "$AUTHORIZED_KEYS_DIR/$PUBLISHER_USER"
else
  echo "No publisher key provided. Place the public key at $AUTHORIZED_KEYS_DIR/$PUBLISHER_USER" >&2
fi

cp "$repo_root/linux/sysctl/99-ftp-hardening.conf" "$SYSCTL_CONF_PATH"

cp "$repo_root/linux/apparmor/usr.sbin.vsftpd" "$APPARMOR_DIR/usr.sbin.vsftpd"
cp "$repo_root/linux/apparmor/usr.lib.openssh.sftp-server" "$APPARMOR_DIR/usr.lib.openssh.sftp-server"

apparmor_parser -r "$APPARMOR_DIR/usr.sbin.vsftpd"
apparmor_parser -r "$APPARMOR_DIR/usr.lib.openssh.sftp-server"

sysctl --system

if [[ -n "$STATIC_IP_CIDR" && -n "$INTERFACE_NAME" ]]; then
  cat > /etc/systemd/network/10-ftp-static.network <<EOF
[Match]
Name=$INTERFACE_NAME

[Network]
Address=$STATIC_IP_CIDR
Gateway=$GATEWAY
DNS=$DNS_SERVERS
EOF

  systemctl enable systemd-networkd
  if systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
    systemctl enable systemd-resolved
  else
    echo "systemd-resolved not found. Configure /etc/resolv.conf manually." >&2
  fi

  if [[ "$RESTART_NETWORKING" == "yes" ]]; then
    systemctl restart systemd-networkd
    if systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
      systemctl restart systemd-resolved
    fi
  else
    echo "Static network config written. Restart networking to apply." >&2
  fi
fi

if [[ "$RESTART_SERVICES" == "yes" ]]; then
  systemctl restart vsftpd
  systemctl restart ssh
fi

echo "Setup complete. Review firewall/rules.md and apply on the upstream firewall."
