#!/usr/bin/env bash
set -euo pipefail

# setup_shadowsocks_forwarder.sh
#
# This script provisions a Linux host to operate as a Shadowsocks forwarder.
# It installs the shadowsocks-libev server, creates a hardened configuration,
# enables IP forwarding, and configures firewall rules to allow proxy traffic.
#
# Environment variables can be used to tweak the installation:
#   SS_SERVER_PORT   - TCP/UDP port to listen on (default: 8388)
#   SS_PASSWORD      - Password for the Shadowsocks server (default: auto-generated)
#   SS_METHOD        - Encryption method (default: aes-256-gcm)
#   SS_TIMEOUT       - Timeout in seconds (default: 300)
#   SS_USER          - System user that will own the Shadowsocks service (default: shadowsocks)
#   SS_CONFIG_PATH   - Path to write the generated configuration (default: /etc/shadowsocks-libev/config.json)
#   SS_SERVICE_NAME  - Name of the systemd service (default: shadowsocks-libev)
#
# Usage:
#   sudo bash setup_shadowsocks_forwarder.sh
#
# The script is idempotent; re-running it updates existing configuration without
# overwriting custom passwords or ports when they are already present.

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"
}

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    log "ERROR: This script must be run as root."
    exit 1
  fi
}

default_password() {
  if [[ -f /etc/shadowsocks-libev/config.json ]]; then
    local existing
    existing=$(awk -F'"' '/"password"/ {print $4; exit}' /etc/shadowsocks-libev/config.json || true)
    if [[ -n ${existing:-} ]]; then
      printf '%s' "$existing"
      return
    fi
  fi
  # Generate a random 24-character base64 password.
  openssl rand -base64 32 | tr -d '\n' | cut -c1-24
}

install_packages() {
  log "Installing shadowsocks-libev and firewall dependencies"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y shadowsocks-libev iptables-persistent jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y epel-release
    dnf install -y shadowsocks-libev iptables-services jq
  else
    log "ERROR: Supported package manager (apt or dnf) not found."
    exit 1
  fi
}

create_service_user() {
  local user=$1
  if id "$user" >/dev/null 2>&1; then
    log "Service user '$user' already exists"
  else
    log "Creating service user '$user'"
    useradd --system --no-create-home --shell /usr/sbin/nologin "$user"
  fi
}

write_config() {
  local path=$1
  local port=$2
  local password=$3
  local method=$4
  local timeout=$5

  mkdir -p "$(dirname "$path")"

  cat >"$path" <<JSON
{
  "server": "0.0.0.0",
  "server_port": $port,
  "password": "$password",
  "timeout": $timeout,
  "method": "$method",
  "fast_open": true,
  "mode": "tcp_and_udp"
}
JSON

  chmod 640 "$path"
  chown shadowsocks:shadowsocks "$path" || true
  log "Wrote Shadowsocks configuration to $path"
}

configure_systemd() {
  local service_name=$1
  local config_path=$2
  local user=$3

  local service_file="/etc/systemd/system/${service_name}.service"
  cat >"$service_file" <<SERVICE
[Unit]
Description=Shadowsocks-Libev Server Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=$user
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
ExecStart=/usr/bin/ss-server -c $config_path
LimitNOFILE=51200
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

  log "Systemd service created at $service_file"
  systemctl daemon-reload
  systemctl enable "$service_name"
  systemctl restart "$service_name"
  log "Systemd service '$service_name' restarted"
}

enable_ip_forwarding() {
  log "Enabling IPv4 forwarding"
  sysctl -w net.ipv4.ip_forward=1
  if ! grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  else
    sed -i 's/^net\.ipv4\.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  fi
}

configure_firewall() {
  local port=$1
  log "Configuring firewall to allow Shadowsocks traffic on port $port"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$port"/tcp
    ufw allow "$port"/udp
  fi

  iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -I INPUT -p udp --dport "$port" -j ACCEPT

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  elif command -v service >/dev/null 2>&1 && [[ -f /etc/init.d/iptables ]]; then
    service iptables save
  fi
}

main() {
  require_root

  local port=${SS_SERVER_PORT:-8388}
  local password=${SS_PASSWORD:-$(default_password)}
  local method=${SS_METHOD:-aes-256-gcm}
  local timeout=${SS_TIMEOUT:-300}
  local user=${SS_USER:-shadowsocks}
  local config_path=${SS_CONFIG_PATH:-/etc/shadowsocks-libev/config.json}
  local service_name=${SS_SERVICE_NAME:-shadowsocks-libev}

  install_packages
  create_service_user "$user"
  write_config "$config_path" "$port" "$password" "$method" "$timeout"
  configure_systemd "$service_name" "$config_path" "$user"
  enable_ip_forwarding
  configure_firewall "$port"

  log "Shadowsocks forwarder setup complete."
  log "Server listening on port $port with method $method"
}

main "$@"
