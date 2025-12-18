#!/usr/bin/env bash
set -euo pipefail

# Ubuntu/Debian one-off host settings for dev boxes
#
# Default behavior (no flags): apply conservative host-level tuning:
# - Enable NTP time sync
# - Increase inotify limits
# - Set higher nofile ulimits
# - Disable apport crash popups
# - Cap systemd-journald disk usage
# - Ensure openssh-client is installed
#
# Optional flags:
#   --no-desktop      Do not apply lid-close suspend disable
#   --no-user-tweaks  Do not apply per-user QoL tweaks
#   --user <name>     User for per-user tweaks (default: invoking user)

DO_DESKTOP=1
DO_USER_TWEAKS=1
TARGET_USER="${SUDO_USER:-$USER}"

log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-desktop) DO_DESKTOP=0; shift ;;
      --no-user-tweaks) DO_USER_TWEAKS=0; shift ;;
      --user) TARGET_USER="$2"; shift 2 ;;
      -h|--help)
        sed -n '1,180p' "$0"
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}


detect_distro() {
  if [[ ! -r /etc/os-release ]]; then
    echo "/etc/os-release not found" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) echo "Unsupported distro: ${ID:-unknown}" >&2; exit 1 ;;
  esac
}

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

enable_ntp() {
  log "Ensuring NTP time sync is enabled"
  if command -v timedatectl >/dev/null 2>&1; then
    sudo timedatectl set-ntp true || true
  fi
}

set_inotify_limits() {
  log "Setting inotify limits"
  sudo tee /etc/sysctl.d/99-dev.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
EOF
  sudo sysctl --system >/dev/null
}

set_ulimits() {
  log "Setting nofile ulimits"
  sudo tee /etc/security/limits.d/99-dev.conf >/dev/null <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
EOF
}

disable_apport() {
  # Ubuntu only; harmless on Debian if file doesn't exist.
  if [[ -f /etc/default/apport ]]; then
    log "Disabling apport crash popups"
    sudo sed -i 's/^enabled=1/enabled=0/' /etc/default/apport || true
  fi
}

cap_journald() {
  log "Capping systemd-journald disk usage"
  sudo mkdir -p /etc/systemd/journald.conf.d
  sudo tee /etc/systemd/journald.conf.d/99-dev.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
  sudo systemctl restart systemd-journald || true
}

ensure_ssh_client() {
  log "Ensuring OpenSSH client is installed"
  ensure_pkg openssh-client
}

disable_lid_close_suspend() {
  log "Disabling lid-close suspend (systemd-logind)"
  sudo mkdir -p /etc/systemd/logind.conf.d
  sudo tee /etc/systemd/logind.conf.d/99-dev.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF
  sudo systemctl restart systemd-logind || true
}

append_if_missing() {
  local file="$1"
  local needle="$2"
  local block="$3"

  sudo -u "$TARGET_USER" mkdir -p "$(dirname "$file")"
  touch "$file"
  chown "$TARGET_USER":"$TARGET_USER" "$file" || true

  if ! grep -qF "$needle" "$file" 2>/dev/null; then
    printf "\n%s\n" "$block" | sudo tee -a "$file" >/dev/null
    sudo chown "$TARGET_USER":"$TARGET_USER" "$file" || true
  fi
}

user_bash_history_tweaks() {
  log "Applying Bash history tweaks for user: $TARGET_USER"
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local block
  block=$'\n# Dev box history defaults\nshopt -s histappend\nPROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a"\nHISTSIZE=100000\nHISTFILESIZE=200000\n'
  append_if_missing "$bashrc" "# Dev box history defaults" "$block"
}

user_ssh_keepalive_config() {
  log "Applying SSH keepalive defaults for user: $TARGET_USER"
  local sshcfg="/home/${TARGET_USER}/.ssh/config"
  local block
  block=$'\nHost *\n  ServerAliveInterval 60\n  ServerAliveCountMax 5\n'
  append_if_missing "$sshcfg" "ServerAliveInterval 60" "$block"
  sudo chmod 600 "$sshcfg" || true
  sudo chown "$TARGET_USER":"$TARGET_USER" "$sshcfg" || true
}

main() {
  parse_args "$@"
  detect_distro

  log "Applying Ubuntu/Debian one-off dev box settings"

  enable_ntp
  set_inotify_limits
  set_ulimits
  disable_apport
  cap_journald
  ensure_ssh_client

  if [[ "$DO_DESKTOP" -eq 1 ]]; then
    disable_lid_close_suspend
  fi

  if [[ "$DO_USER_TWEAKS" -eq 1 ]]; then
    user_bash_history_tweaks
    user_ssh_keepalive_config
  fi

  log "Done"
}

main "$@"
