#!/usr/bin/env bash
set -euo pipefail

# Ubuntu/Debian image cleanup script
# Purpose: make the box safe/clean for imaging (golden image/template).
#
# What it does:
# - apt clean + autoremove
# - clears temp directories and common caches
# - vacuums journald + truncates log files
# - resets machine-id
# - removes SSH host keys (regenerated on first boot)
# - removes user shell histories
# - optionally runs cloud-init clean (if installed)
#
# Usage:
#   sudo bash setup-clean.sh
#
# Optional flags:
#   --keep-ssh-host-keys     Do not remove /etc/ssh/ssh_host_*
#   --keep-machine-id        Do not reset machine-id
#   --keep-logs              Do not truncate logs or vacuum journald
#   --keep-user-history      Do not remove shell histories
#   --keep-caches            Do not remove user caches
#   --cloud-init-clean       Run cloud-init clean (only if cloud-init present)
#   --no-shutdown            Do not shutdown after cleanup

KEEP_SSH_HOST_KEYS=0
KEEP_MACHINE_ID=0
KEEP_LOGS=0
KEEP_USER_HISTORY=0
KEEP_CACHES=0
DO_CLOUD_INIT_CLEAN=0
NO_SHUTDOWN=0

log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-ssh-host-keys) KEEP_SSH_HOST_KEYS=1; shift ;;
      --keep-machine-id) KEEP_MACHINE_ID=1; shift ;;
      --keep-logs) KEEP_LOGS=1; shift ;;
      --keep-user-history) KEEP_USER_HISTORY=1; shift ;;
      --keep-caches) KEEP_CACHES=1; shift ;;
      --cloud-init-clean) DO_CLOUD_INIT_CLEAN=1; shift ;;
      --no-shutdown) NO_SHUTDOWN=1; shift ;;
      -h|--help)
        sed -n '1,220p' "$0"
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (use sudo)." >&2
    exit 1
  fi
}

apt_cleanup() {
  log "APT cleanup"
  apt-get update -y || true
  apt-get autoremove --purge -y || true
  apt-get clean || true
  rm -rf /var/lib/apt/lists/* || true
}

logs_cleanup() {
  if [[ "$KEEP_LOGS" -eq 1 ]]; then
    log "Skipping logs cleanup (--keep-logs)"
    return 0
  fi

  log "Vacuuming journald"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --rotate || true
    journalctl --vacuum-time=1s || true
  fi

  log "Truncating common log files"
  # Truncate regular files under /var/log (avoid directories, sockets, etc.)
  find /var/log -type f -exec truncate -s 0 {} \; || true

  # Remove rotated/compressed logs if present
  find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete || true
}

machine_id_reset() {
  if [[ "$KEEP_MACHINE_ID" -eq 1 ]]; then
    log "Skipping machine-id reset (--keep-machine-id)"
    return 0
  fi

  log "Resetting machine-id"
  # systemd uses /etc/machine-id, sometimes also /var/lib/dbus/machine-id
  truncate -s 0 /etc/machine-id || true
  rm -f /var/lib/dbus/machine-id || true
  ln -sf /etc/machine-id /var/lib/dbus/machine-id || true
}

ssh_host_keys_cleanup() {
  if [[ "$KEEP_SSH_HOST_KEYS" -eq 1 ]]; then
    log "Skipping SSH host key removal (--keep-ssh-host-keys)"
    return 0
  fi

  log "Removing SSH host keys (will be regenerated on first boot)"
  rm -f /etc/ssh/ssh_host_* || true
}

cloud_init_cleanup() {
  if [[ "$DO_CLOUD_INIT_CLEAN" -ne 1 ]]; then
    return 0
  fi

  if command -v cloud-init >/dev/null 2>&1; then
    log "Running cloud-init clean"
    cloud-init clean --logs || cloud-init clean || true
    rm -rf /var/lib/cloud/instances/* || true
  else
    log "cloud-init not installed; skipping --cloud-init-clean"
  fi
}

temp_cleanup() {
  log "Cleaning temp directories"
  rm -rf /tmp/* /var/tmp/* || true
}

user_history_cleanup() {
  if [[ "$KEEP_USER_HISTORY" -eq 1 ]]; then
    log "Skipping user history cleanup (--keep-user-history)"
    return 0
  fi

  log "Removing user shell histories"
  # Root + all users under /home
  rm -f /root/.bash_history /root/.zsh_history /root/.lesshst /root/.python_history 2>/dev/null || true
  for d in /home/*; do
    [[ -d "$d" ]] || continue
    rm -f "$d/.bash_history" "$d/.zsh_history" "$d/.lesshst" "$d/.python_history" 2>/dev/null || true
  done
}

user_cache_cleanup() {
  if [[ "$KEEP_CACHES" -eq 1 ]]; then
    log "Skipping caches cleanup (--keep-caches)"
    return 0
  fi

  log "Cleaning user caches"
  rm -rf /root/.cache/* 2>/dev/null || true
  for d in /home/*; do
    [[ -d "$d" ]] || continue
    rm -rf "$d/.cache/"* 2>/dev/null || true
  done
}

remove_sensitive_artifacts() {
  log "Removing common sensitive artifacts"
  # SSH known_hosts (host-specific)
  rm -f /root/.ssh/known_hosts 2>/dev/null || true
  for d in /home/*; do
    [[ -d "$d" ]] || continue
    rm -f "$d/.ssh/known_hosts" 2>/dev/null || true
  done

  # Leftover editor swap files in home dirs (best-effort)
  find /home /root -maxdepth 4 -type f \( -name "*.swp" -o -name "*~" \) -delete 2>/dev/null || true
}

final_sync() {
  log "Syncing filesystem"
  sync || true
}

main() {
  parse_args "$@"
  need_root

  log "Starting image cleanup"
  apt_cleanup
  logs_cleanup
  temp_cleanup
  user_history_cleanup
  user_cache_cleanup
  remove_sensitive_artifacts
  ssh_host_keys_cleanup
  machine_id_reset
  cloud_init_cleanup
  final_sync

  log "Image cleanup complete"
  log "Recommended: power off now and capture the image (do not reboot if you removed SSH host keys and machine-id)."
  
  if [[ "$NO_SHUTDOWN" -eq 1 ]]; then
    log "Skipping automatic shutdown (--no-shutdown)"
    exit 0
  fi
  
  log "Shutting down in 10 sec... (Ctrl-C to abort)"
  sleep 10
  shutdown -h now
}

main "$@"
