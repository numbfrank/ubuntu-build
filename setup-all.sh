#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Ubuntu Dev Box Setup - All-in-One Script
# =============================================================================
#
# Usage:
#   sudo bash setup-all.sh [command] [options]
#   bash setup-all.sh --headless --dry-run
#
# Commands:
#   all          Run dev + env setup (default)
#   dev          Install development tools only
#   env          Apply system/user configuration only
#   clean        Prepare system for imaging
#   update       Update all installed tools
#
# Options:
#   --headless         Server/console install: no GUI apps or desktop settings
#   --desktop          Install Ubuntu Desktop GUI and desktop apps
#   --console, --gui   Aliases for --headless and --desktop
#   --force, -f        Force re-run even if already completed
#   --no-desktop       Alias for --headless
#   --no-user-tweaks   Skip per-user configurations
#   --current-user     Apply config to current user only (do not create dev user)
#   --dev-user         Create dev user and apply config to dev only
#   --user NAME        Apply config to NAME only (create dev only if NAME is 'dev')
#   --no-dev-user      Don't create the 'dev' user (same as --current-user)
#   --no-shutdown      Don't shutdown after clean (for clean command)
#   --uk-settings      Set UK locale, keyboard and timezone
#   --ssh-server       Install and enable OpenSSH server
#   --reboot           Reboot after successful full setup
#   --dry-run          Show what would run without executing
#   -h, --help         Show this help message
#
# By default, creates and configures dev with password dev and normal sudo.
# Existing dev passwords are preserved.
#
# Examples:
#   sudo bash setup-all.sh                  # Auto-detect desktop; dev user
#   sudo bash setup-all.sh --headless       # Headless server
#   sudo bash setup-all.sh --desktop        # Install Ubuntu Desktop GUI
#   sudo bash setup-all.sh --current-user   # Configure invoking user instead
#   sudo bash setup-all.sh dev --headless   # CLI development tools only

# =============================================================================
# Configuration
# =============================================================================

COMMAND="all"
COMMAND_SET=0
DRY_RUN=0
DO_UPDATE=0
UPDATE_ONLY=0
DO_USER_TWEAKS=1
CREATE_DEV_USER=1
INSTALL_GUI=0
INSTALL_PROFILE="auto"
RESOLVED_PROFILE=""
NO_SHUTDOWN=0
REBOOT_AFTER=0
FORCE_RERUN=0
TARGET_USER="dev"
TARGET_HOME=""
USER_SELECTION="default"
APPLY_UK_SETTINGS=0
INSTALL_SSH_SERVER=0

# Marker file to track completed setup
SETUP_MARKER="/etc/ubuntu-devbox-setup-complete"

# Clean command options
KEEP_SSH_HOST_KEYS=0
KEEP_MACHINE_ID=0
KEEP_LOGS=0
KEEP_USER_HISTORY=0
KEEP_CACHES=0
DO_CLOUD_INIT_CLEAN=0

# Distro detection
DIST_ID=""
DIST_CODENAME=""

# =============================================================================
# Colors and Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { printf "\n${BLUE}[%s]${NC} %s\n" "$(date +'%F %T')" "$*"; }
success() { printf "${GREEN}[%s] ✓${NC} %s\n" "$(date +'%F %T')" "$*"; }
warn()    { printf "${YELLOW}[%s] ⚠${NC} %s\n" "$(date +'%F %T')" "$*"; }
error()   { printf "${RED}[%s] ✗${NC} %s\n" "$(date +'%F %T')" "$*" >&2; }

# =============================================================================
# Argument Parsing
# =============================================================================

usage() {
  cat <<'EOF'
Usage: sudo bash setup-all.sh [all|dev|env|clean|update] [options]

Install profiles:
  (default)         Use desktop profile if GNOME is installed, otherwise headless
  --desktop, --gui  Install GNOME and desktop applications
  --headless, --console, --no-desktop
                    Skip desktop applications and settings

User selection:
  (default)         Create/configure dev (password dev; normal sudo)
  --current-user    Configure only the user who invoked sudo
  --user NAME       Configure an existing user (create one only for NAME=dev)
  --dev-user        Create and configure dev (password dev if new)
  --no-dev-user     Alias for --current-user
  --no-user-tweaks  Skip per-user shell configuration
  --uk-settings     Set en_GB locale, UK keyboard and Europe/London timezone
  --ssh-server      Install and enable OpenSSH server

Other options:
  --force, -f       Rerun a completed full setup
  --reboot          Reboot after a successful full setup
  --dry-run         Print resolved choices without changing the system
  --update          Upgrade packages during the dev command
  --update-only     Update installed development tools only
  --no-shutdown     Do not shut down after clean
  --keep-ssh-host-keys, --keep-machine-id, --keep-logs,
  --keep-user-history, --keep-caches, --cloud-init-clean
                    Clean command options
  -h, --help        Show this message
EOF
  exit 0
}

set_install_profile() {
  local requested="$1"
  if [[ "$INSTALL_PROFILE" != "auto" && "$INSTALL_PROFILE" != "$requested" ]]; then
    error "Conflicting install profiles: $INSTALL_PROFILE and $requested"
    exit 2
  fi
  INSTALL_PROFILE="$requested"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      all|dev|env|clean|update)
        if [[ "$COMMAND_SET" -eq 1 ]]; then
          error "Specify only one command"
          exit 2
        fi
        COMMAND="$1"
        COMMAND_SET=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        ;;
      # Dev options
      --update)
        DO_UPDATE=1
        shift
        ;;
      --update-only)
        UPDATE_ONLY=1
        DO_UPDATE=1
        shift
        ;;
      # Env options
      --gui|--desktop)
        set_install_profile desktop
        shift
        ;;
      --console|--headless|--no-desktop)
        set_install_profile headless
        shift
        ;;
      --no-user-tweaks)
        DO_USER_TWEAKS=0
        shift
        ;;
      --uk-settings)
        APPLY_UK_SETTINGS=1
        shift
        ;;
      --ssh-server)
        INSTALL_SSH_SERVER=1
        shift
        ;;
      --current-user)
        CREATE_DEV_USER=0
        TARGET_USER="${SUDO_USER:-${USER:-}}"
        USER_SELECTION="current"
        shift
        ;;
      --dev-user)
        CREATE_DEV_USER=1
        TARGET_USER="dev"
        USER_SELECTION="dev"
        shift
        ;;
      --no-dev-user)
        CREATE_DEV_USER=0
        TARGET_USER="${SUDO_USER:-${USER:-}}"
        USER_SELECTION="current"
        shift
        ;;
      --force|-f)
        FORCE_RERUN=1
        shift
        ;;
      --user)
        if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
          error "--user requires a username"
          exit 2
        fi
        TARGET_USER="$2"
        USER_SELECTION="named"
        # Apply to this user only: create dev only if target is dev
        if [[ "$2" == "dev" ]]; then
          CREATE_DEV_USER=1
        else
          CREATE_DEV_USER=0
        fi
        shift 2
        ;;
      # Clean options
      --no-shutdown)
        NO_SHUTDOWN=1
        shift
        ;;
      --reboot)
        REBOOT_AFTER=1
        shift
        ;;
      --keep-ssh-host-keys)
        KEEP_SSH_HOST_KEYS=1
        shift
        ;;
      --keep-machine-id)
        KEEP_MACHINE_ID=1
        shift
        ;;
      --keep-logs)
        KEEP_LOGS=1
        shift
        ;;
      --keep-user-history)
        KEEP_USER_HISTORY=1
        shift
        ;;
      --keep-caches)
        KEEP_CACHES=1
        shift
        ;;
      --cloud-init-clean)
        DO_CLOUD_INIT_CLEAN=1
        shift
        ;;
      *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
}

resolve_install_profile() {
  case "$INSTALL_PROFILE" in
    desktop|headless)
      RESOLVED_PROFILE="$INSTALL_PROFILE"
      ;;
    auto)
      if pkg_installed ubuntu-desktop || pkg_installed gnome-shell || pkg_installed task-gnome-desktop; then
        RESOLVED_PROFILE="desktop"
      else
        RESOLVED_PROFILE="headless"
      fi
      ;;
  esac
  if [[ "$INSTALL_PROFILE" == "desktop" ]]; then
    INSTALL_GUI=1
  fi
}

resolve_target_user() {
  if [[ "$COMMAND" != "all" && "$COMMAND" != "env" ]]; then
    return 0
  fi
  if [[ -z "$TARGET_USER" || ( "$USER_SELECTION" != "named" && "$TARGET_USER" == "root" ) ]]; then
    error "No sudo invoking user found. Pass --user NAME or --dev-user."
    exit 2
  fi

  local account
  account="$(getent passwd "$TARGET_USER" || true)"
  if [[ -z "$account" ]]; then
    if [[ "$TARGET_USER" == "dev" && "$CREATE_DEV_USER" -eq 1 ]]; then
      TARGET_HOME="/home/dev"
      return 0
    fi
    error "User '$TARGET_USER' does not exist"
    exit 2
  fi
  TARGET_HOME="$(cut -d: -f6 <<<"$account")"
  if [[ "$TARGET_HOME" != /* || ! -d "$TARGET_HOME" ]]; then
    error "User '$TARGET_USER' has no usable home directory: $TARGET_HOME"
    exit 2
  fi
}

show_plan() {
  log "Command: $COMMAND"
  if [[ "$COMMAND" == "clean" ]]; then
    log "Cleanup: image logs, caches, history, host keys and machine identity"
    log "Shutdown: $([[ "$NO_SHUTDOWN" -eq 1 ]] && echo no || echo yes)"
    return 0
  fi

  local runs_dev=0 runs_env=0
  case "$COMMAND" in
    all) runs_dev=1; runs_env=1 ;;
    dev|update) runs_dev=1 ;;
    env) runs_env=1 ;;
  esac

  log "Profile: $RESOLVED_PROFILE (requested: $INSTALL_PROFILE)"
  if [[ "$runs_dev" -eq 1 ]]; then
    if [[ "$COMMAND" == "update" || "$UPDATE_ONLY" -eq 1 ]]; then
      log "Docker: update installed engine to latest Docker CE (skip if absent)"
    elif pkg_installed docker.io && ! pkg_installed docker-ce; then
      log "Docker: replace existing docker.io with latest Docker CE"
    else
      log "Docker: install or refresh latest Docker CE"
    fi
  fi
  if [[ "$RESOLVED_PROFILE" == "desktop" ]]; then
    if [[ "$runs_dev" -eq 1 ]]; then
      case "$(dpkg --print-architecture 2>/dev/null || true)" in
        amd64) log "GUI packages: yes (VS Code and Chrome)" ;;
        arm64|armhf) log "GUI packages: yes (VS Code; Chrome unavailable on this architecture)" ;;
        *) log "GUI packages: no (VS Code and Chrome unavailable on this architecture)" ;;
      esac
    else
      log "GUI packages: no (env configures the desktop only)"
    fi
    if [[ "$runs_env" -eq 1 ]]; then
      log "Desktop font: Hack Nerd Font"
      if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
        log "Dev background: apply at next GNOME login"
      fi
      if [[ "$INSTALL_GUI" -eq 1 ]]; then
        log "Desktop installation: yes"
      else
        log "Desktop installation: already present"
      fi
    else
      log "Desktop installation: no (dev/update installs tools only)"
    fi
  else
    log "GUI packages: no (headless profile)"
    log "Desktop installation: no"
  fi

  if [[ "$runs_env" -eq 1 ]]; then
    log "Target user: $TARGET_USER"
    log "Create dev user: $([[ "$CREATE_DEV_USER" -eq 1 ]] && echo yes || echo no)"
    log "UK settings: $([[ "$APPLY_UK_SETTINGS" -eq 1 ]] && echo yes || echo no)"
    log "SSH server: $([[ "$INSTALL_SSH_SERVER" -eq 1 ]] && echo yes || echo no)"
  else
    log "Target user: not used"
  fi
  log "Reboot: $([[ "$REBOOT_AFTER" -eq 1 ]] && echo yes || echo no)"
}

validate_command_options() {
  if [[ "$COMMAND" == "clean" && "$INSTALL_PROFILE" != "auto" ]]; then
    error "Install profile options do not apply to clean"
    exit 2
  fi
  if [[ "$COMMAND" != "all" && "$REBOOT_AFTER" -eq 1 ]]; then
    error "--reboot applies only to all"
    exit 2
  fi
  if [[ "$COMMAND" != "clean" && ( "$NO_SHUTDOWN" -eq 1 || "$KEEP_SSH_HOST_KEYS" -eq 1 || "$KEEP_MACHINE_ID" -eq 1 || "$KEEP_LOGS" -eq 1 || "$KEEP_USER_HISTORY" -eq 1 || "$KEEP_CACHES" -eq 1 || "$DO_CLOUD_INIT_CLEAN" -eq 1 ) ]]; then
    error "Clean options require the clean command"
    exit 2
  fi
  if [[ "$COMMAND" != "all" && "$COMMAND" != "env" ]]; then
    if [[ "$USER_SELECTION" != "default" || "$DO_USER_TWEAKS" -eq 0 || "$APPLY_UK_SETTINGS" -eq 1 || "$INSTALL_SSH_SERVER" -eq 1 ]]; then
      error "User and environment options require all or env"
      exit 2
    fi
  fi
  if [[ "$COMMAND" != "all" && "$FORCE_RERUN" -eq 1 ]]; then
    error "--force applies only to all"
    exit 2
  fi
  if [[ "$COMMAND" != "dev" && "$UPDATE_ONLY" -eq 1 ]]; then
    error "--update-only applies only to dev"
    exit 2
  fi
  if [[ "$COMMAND" != "all" && "$COMMAND" != "dev" && "$COMMAND" != "update" && "$DO_UPDATE" -eq 1 ]]; then
    error "--update applies only to all or dev"
    exit 2
  fi
}

# =============================================================================
# Utility Functions
# =============================================================================

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
  fi
}

detect_distro() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS - /etc/os-release not found"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian)
      DIST_ID="$ID"
      DIST_CODENAME="${VERSION_CODENAME:-}"
      log "Detected: ${PRETTY_NAME:-$ID}"
      if [[ -z "$DIST_CODENAME" ]]; then
        error "OS codename is unavailable; cannot configure third-party package repositories"
        exit 1
      fi
      ;;
    *)
      error "Unsupported OS: ${ID:-unknown}. Supports Ubuntu/Debian only."
      exit 1
      ;;
  esac
}

pkg_installed() {
  local status
  status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" || return 1
  [[ "${status:1:1}" == i ]]
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  if ! pkg_installed "$pkg"; then
    apt-get update -y
    apt-get install -y "$pkg"
  fi
}

add_gpg_key() {
  local url="$1"
  local keyring="$2"
  if [[ ! -f "$keyring" ]]; then
    curl -fsSL "$url" | gpg --dearmor --yes -o "$keyring"
    chmod a+r "$keyring"
  fi
}

add_apt_repo() {
  local list_file="$1"
  local repo_line="$2"
  if [[ ! -f "$list_file" ]] || [[ "$(cat "$list_file")" != "$repo_line" ]]; then
    printf '%s\n' "$repo_line" > "$list_file"
  fi
}

run_gsettings() {
  local schema="$1"
  local key="$2"
  local value="$3"
  local dbus_addr="unix:path=/run/user/$(id -u "$TARGET_USER")/bus"
  sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
    gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

append_if_missing() {
  local file="$1"
  local needle="$2"
  local block="$3"

  sudo -u "$TARGET_USER" mkdir -p "$(dirname "$file")"
  sudo -u "$TARGET_USER" touch "$file"

  if ! grep -qF "$needle" "$file" 2>/dev/null; then
    printf "\n%s\n" "$block" | sudo -u "$TARGET_USER" tee -a "$file" >/dev/null
  fi
}

# =============================================================================
# DEV: Installation Functions
# =============================================================================

apt_update() {
  apt-get update -y
}

apt_upgrade() {
  log "Upgrading system packages"
  apt-get upgrade -y
}

install_core_packages() {
  log "Installing core dev packages"
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    software-properties-common \
    apt-transport-https \
    build-essential \
    git \
    git-lfs \
    python3 \
    python3-pip \
    python3-venv \
    tmux \
    jq \
    ripgrep \
    fd-find \
    bat \
    fzf \
    htop \
    tree \
    unzip \
    vim

  ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
  ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true
}

setup_git_lfs() {
  if cmd_exists git && cmd_exists git-lfs; then
    git lfs install --system >/dev/null 2>&1 || true
  fi
}

install_or_update_delta() {
  if cmd_exists delta; then
    log "git-delta is already installed; leaving its version unchanged"
    return 0
  fi
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    log "git-delta not installed; skipping (update-only mode)"
    return 0
  fi

  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    warn "git-delta .deb installer supports amd64 only; skipping"
    return 0
  fi

  log "Installing or updating git-delta"
  local version="0.17.0"
  local deb_url="https://github.com/dandavison/delta/releases/download/${version}/git-delta_${version}_amd64.deb"
  local tmp_deb
  tmp_deb="$(mktemp --suffix=.deb)"
  
  curl -fsSL "$deb_url" -o "$tmp_deb"
  dpkg -i "$tmp_deb" || apt-get install -f -y
  rm -f "$tmp_deb"
}

install_or_update_zoxide() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists zoxide; then
    log "zoxide not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating zoxide"
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | \
    sh -s -- --bin-dir /usr/local/bin --man-dir /usr/local/share/man
}

ensure_hashicorp_repo() {
  add_gpg_key "https://apt.releases.hashicorp.com/gpg" "/usr/share/keyrings/hashicorp.gpg"
  add_apt_repo "/etc/apt/sources.list.d/hashicorp.list" \
    "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${DIST_CODENAME} main"
}

ensure_docker_repo() {
  install -m 0755 -d /etc/apt/keyrings
  add_gpg_key "https://download.docker.com/linux/${DIST_ID}/gpg" "/etc/apt/keyrings/docker.gpg"
  add_apt_repo "/etc/apt/sources.list.d/docker.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DIST_ID} ${DIST_CODENAME} stable"
}

ensure_vscode_repo() {
  # Respect an existing VS Code source, including deb822 .sources files.
  local source
  for source in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "$source" && "$source" != "/etc/apt/sources.list.d/vscode.list" ]] || continue
    if grep -q 'packages.microsoft.com/repos/code' "$source"; then
      log "Using existing VS Code repository: $source"
      return 0
    fi
  done
  
  add_gpg_key "https://packages.microsoft.com/keys/microsoft.asc" "/usr/share/keyrings/vscode.gpg"
  add_apt_repo "/etc/apt/sources.list.d/vscode.list" \
    "deb [signed-by=/usr/share/keyrings/vscode.gpg arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main"
}

ensure_github_cli_repo() {
  add_gpg_key "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "/usr/share/keyrings/githubcli-archive-keyring.gpg"
  add_apt_repo "/etc/apt/sources.list.d/github-cli.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
}

ensure_chrome_repo() {
  add_gpg_key "https://dl.google.com/linux/linux_signing_key.pub" "/usr/share/keyrings/google-chrome.gpg"
  add_apt_repo "/etc/apt/sources.list.d/google-chrome.list" \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main"
}

install_or_update_starship() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists starship; then
    log "Starship not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating Starship"
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y

}

install_or_update_docker() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed docker.io && ! pkg_installed docker-ce; then
    log "Docker not installed; skipping (update-only mode)"
    return 0
  fi

  local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  local conflicts=(docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc)
  local installed_conflicts=()
  local removal_specs=()
  local package candidate

  log "Installing latest Docker CE from Docker's stable repository"
  ensure_docker_repo
  apt_update

  # Confirm the complete replacement is available before changing an existing engine.
  for package in "${packages[@]}"; do
    candidate="$(LC_ALL=C apt-cache policy "$package" | awk '$1 == "Candidate:" { print $2; exit }')"
    if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
      error "No APT candidate for $package; leaving the existing Docker installation in place"
      return 1
    fi
  done

  for package in "${conflicts[@]}"; do
    if pkg_installed "$package"; then
      installed_conflicts+=("$package")
      removal_specs+=("${package}-")
    fi
  done
  if [[ "${#installed_conflicts[@]}" -gt 0 ]]; then
    log "Replacing conflicting Docker packages: ${installed_conflicts[*]}"
  fi

  # APT resolves installation and removals together; package- requests removal.
  apt-get install -y "${packages[@]}" "${removal_specs[@]}"
  systemctl enable --now docker
  groupadd -f docker
}

install_or_update_hashicorp() {
  local packages=(terraform packer)
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    packages=()
    pkg_installed terraform && packages+=(terraform)
    pkg_installed packer && packages+=(packer)
    if [[ "${#packages[@]}" -eq 0 ]]; then
      log "Terraform/Packer not installed; skipping (update-only mode)"
      return 0
    fi
  fi

  log "Installing Terraform and Packer"
  ensure_hashicorp_repo
  apt_update
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    apt-get install -y --only-upgrade "${packages[@]}"
  else
    apt-get install -y "${packages[@]}"
  fi
}

install_or_update_awscli() {
  if [[ "$UPDATE_ONLY" -eq 1 && ! -d /usr/local/aws-cli/v2/current ]]; then
    log "AWS CLI v2 installer is not present; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating AWS CLI v2"
  local tmp="$(mktemp -d)"
  local aws_arch
  case "$(dpkg --print-architecture)" in
    amd64) aws_arch="x86_64" ;;
    arm64) aws_arch="aarch64" ;;
    *) warn "AWS CLI installer is unavailable for this architecture; skipping"; rm -rf "$tmp"; return 0 ;;
  esac
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$tmp/aws.zip"
  unzip -q "$tmp/aws.zip" -d "$tmp"
  if [[ -d /usr/local/aws-cli/v2/current ]]; then
    "$tmp/aws/install" --update
  else
    "$tmp/aws/install"
  fi
  rm -rf "$tmp"
}

install_or_update_vscode() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed code; then
    log "VS Code not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating VS Code"
  ensure_vscode_repo
  apt_update
  apt-get install -y code
}

install_or_update_github_cli() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed gh; then
    log "GitHub CLI not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating GitHub CLI"
  ensure_github_cli_repo
  apt_update
  apt-get install -y gh
}

install_or_update_chrome() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed google-chrome-stable; then
    log "Google Chrome not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating Google Chrome"
  ensure_chrome_repo
  apt_update
  apt-get install -y google-chrome-stable
}

# =============================================================================
# ENV: System Configuration Functions
# =============================================================================

enable_ntp() {
  log "Ensuring NTP time sync is enabled"
  if cmd_exists timedatectl; then
    timedatectl set-ntp true || true
  fi
}

set_inotify_limits() {
  log "Setting inotify limits"
  tee /etc/sysctl.d/99-dev.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
EOF
  sysctl --system >/dev/null
}

set_ulimits() {
  log "Setting nofile ulimits"
  tee /etc/security/limits.d/99-dev.conf >/dev/null <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
EOF
}

disable_apport() {
  if [[ -f /etc/default/apport ]]; then
    log "Disabling apport crash popups"
    sed -i 's/^enabled=1/enabled=0/' /etc/default/apport || true
  fi
}

cap_journald() {
  log "Capping systemd-journald disk usage"
  mkdir -p /etc/systemd/journald.conf.d
  tee /etc/systemd/journald.conf.d/99-dev.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
  systemctl restart systemd-journald || true
}

ensure_ssh_client() {
  log "Ensuring OpenSSH client is installed"
  ensure_pkg openssh-client
  if [[ "$INSTALL_SSH_SERVER" -eq 1 ]]; then
    log "Installing and enabling OpenSSH server"
    ensure_pkg openssh-server
    systemctl enable --now ssh
  fi
}

create_dev_user() {
  local dev_user="dev"
  
  if id "$dev_user" &>/dev/null; then
    log "Existing dev account found; preserving its password"
    usermod -aG sudo "$dev_user"
  else
    log "Creating user '$dev_user' with password dev and normal sudo"
    useradd -m -s /bin/bash -G sudo "$dev_user"
    printf '%s\n' 'dev:dev' | chpasswd
  fi

  # Remove only the insecure rule written by older versions of this script.
  local legacy_sudoers="/etc/sudoers.d/90-dev-nopasswd"
  if [[ -r "$legacy_sudoers" ]] && [[ "$(tr -d '\n' < "$legacy_sudoers")" == "dev ALL=(ALL) NOPASSWD:ALL" ]]; then
    rm -f "$legacy_sudoers"
    log "Removed legacy passwordless sudo rule for dev"
  fi

  TARGET_HOME="$(getent passwd dev | cut -d: -f6)"
  log "Dev user setup complete"
}

set_uk_locale() {
  log "Setting UK locale, keyboard, and timezone"
  apt-get install -y locales
  locale-gen en_GB.UTF-8
  update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8
  timedatectl set-timezone Europe/London || true
  
  tee /etc/default/keyboard >/dev/null <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
  dpkg-reconfigure -f noninteractive keyboard-configuration || true
  
  if [[ "$RESOLVED_PROFILE" == "desktop" ]] && cmd_exists gsettings; then
    run_gsettings org.gnome.desktop.input-sources sources "[('xkb', 'gb')]"
  fi
}

install_nerd_fonts() {
  log "Installing Hack Nerd Font"
  
  local font_dir="/usr/share/fonts/truetype/hack-nerd"
  if [[ -d "$font_dir" ]]; then
    log "Hack Nerd Font already installed"
    return 0
  fi
  
  local version="3.3.0"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/Hack.zip" -o "$tmp_dir/Hack.zip"
  mkdir -p "$font_dir"
  unzip -q "$tmp_dir/Hack.zip" -d "$font_dir"
  rm -rf "$tmp_dir"
  
  fc-cache -f -v >/dev/null 2>&1 || true
  log "Hack Nerd Font installed"
}

install_dev_background() {
  log "Installing GNOME background for dev"

  local script_dir background_source tmp_dir=""
  script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
  background_source="$script_dir/files/dev-background.png"
  if [[ ! -f "$background_source" ]]; then
    tmp_dir="$(mktemp -d)"
    background_source="$tmp_dir/dev-background.png"
    curl -fsSL --retry 3 \
      "https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/files/dev-background.png" \
      -o "$background_source"
  fi
  install -Dm644 "$background_source" /usr/share/backgrounds/dev-background.png
  if [[ -n "$tmp_dir" ]]; then
    rm -rf -- "$tmp_dir"
  fi

  install -d -m755 /usr/local/lib/ubuntu-build
  cat > /usr/local/lib/ubuntu-build/set-dev-background <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
uri="file:///usr/share/backgrounds/dev-background.png"
gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri" 2>/dev/null || true
gsettings set org.gnome.desktop.background picture-options zoom
rm -f -- "$HOME/.config/autostart/dev-background.desktop"
EOF
  chmod 755 /usr/local/lib/ubuntu-build/set-dev-background

  local autostart_dir="$TARGET_HOME/.config/autostart"
  sudo -u dev mkdir -p "$autostart_dir"
  sudo -u dev tee "$autostart_dir/dev-background.desktop" >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Set Dev Background
Exec=/usr/local/lib/ubuntu-build/set-dev-background
TryExec=/usr/bin/gsettings
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  log "Dev background will be applied at the next GNOME login"
}

install_ubuntu_desktop() {
  log "Installing desktop environment"
  case "$DIST_ID" in
    ubuntu) DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop ;;
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop ;;
  esac
  systemctl set-default graphical.target
  if systemctl list-unit-files gdm3.service --no-legend 2>/dev/null | grep -q gdm3; then
    systemctl enable gdm3
  elif systemctl list-unit-files gdm.service --no-legend 2>/dev/null | grep -q gdm; then
    systemctl enable gdm
  fi
  log "Desktop installed; reboot to start the graphical login"
}

disable_browser_first_run() {
  log "Disabling browser first-run prompts"
  
  # Firefox policies
  mkdir -p /etc/firefox/policies
  tee /etc/firefox/policies/policies.json >/dev/null <<'EOF'
{
  "policies": {
    "DisableProfileImport": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": ""
  }
}
EOF

  # Chrome policies
  mkdir -p /etc/opt/chrome/policies/managed
  tee /etc/opt/chrome/policies/managed/no-first-run.json >/dev/null <<'EOF'
{
  "WelcomePageOnOSUpgradeEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false
}
EOF

  # Chromium policies
  mkdir -p /etc/chromium/policies/managed
  tee /etc/chromium/policies/managed/no-first-run.json >/dev/null <<'EOF'
{
  "WelcomePageOnOSUpgradeEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false
}
EOF
}

user_bash_history_tweaks() {
  log "Applying Bash history tweaks for user: $TARGET_USER"
  local bashrc="${TARGET_HOME}/.bashrc"
  local block
  read -r -d '' block <<'EOF' || true
# Dev box history defaults
shopt -s histappend
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a"
HISTSIZE=100000
HISTFILESIZE=200000
EOF
  append_if_missing "$bashrc" "# Dev box history defaults" "$block"
}

user_ssh_keepalive_config() {
  log "Applying SSH keepalive defaults for user: $TARGET_USER"
  local sshcfg="${TARGET_HOME}/.ssh/config"
  local block
  read -r -d '' block <<'EOF' || true
Host *
  ServerAliveInterval 60
  ServerAliveCountMax 5
EOF
  append_if_missing "$sshcfg" "ServerAliveInterval 60" "$block"
  sudo -u "$TARGET_USER" chmod 700 "${TARGET_HOME}/.ssh"
  sudo -u "$TARGET_USER" chmod 600 "$sshcfg"
}

add_common_aliases() {
  log "Adding common dev aliases for user: $TARGET_USER"
  
  local bashrc="${TARGET_HOME}/.bashrc"
  local aliases_block
  read -r -d '' aliases_block <<'EOF' || true
# Common dev aliases

# Git shortcuts
alias gs="git status"
alias gp="git pull"
alias gc="git commit"
alias gco="git checkout"
alias gb="git branch"
alias gl="git log --oneline --graph --decorate"
alias gd="git diff"
alias gundo="git reset --soft HEAD~1"
alias gamend="git commit --amend"
alias gstash="git stash save"
alias gpop="git stash pop"
alias gupdate="git fetch origin && git rebase origin/main"

# Terraform shortcuts
alias tf="terraform"
alias tfi="terraform init"
alias tfp="terraform plan"
alias tfa="terraform apply"
alias tfd="terraform destroy"

# Navigation
alias ..="cd .."
alias ...="cd ../.."

# System info
alias ports="netstat -tulanp"
alias listening="netstat -tlnp"
alias meminfo="free -h"
alias diskinfo="df -h"
alias cpuinfo="lscpu"
alias myip="curl -s ifconfig.me"

# List aliases
alias ll="ls -lah"
alias la="ls -A"

EOF
  
  append_if_missing "$bashrc" "# Common dev aliases" "$aliases_block"
}

setup_shell_integrations() {
  log "Setting up shell integrations for user: $TARGET_USER"
  
  local bashrc="${TARGET_HOME}/.bashrc"
  
  # FZF integration
  local fzf_block
  read -r -d '' fzf_block <<'EOF' || true
# FZF shell integration
if command -v fzf >/dev/null 2>&1; then
  # Try new --bash flag first, fall back to sourcing scripts
  if fzf --bash &>/dev/null; then
    eval "$(fzf --bash)"
  elif [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
    source /usr/share/doc/fzf/examples/completion.bash 2>/dev/null || true
  fi
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
fi
EOF
  
  # Zoxide integration
  local zoxide_block
  read -r -d '' zoxide_block <<'EOF' || true
# Zoxide integration
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
  alias cd="z"
fi
EOF
  
  # Shell functions
  local functions_block
  read -r -d '' functions_block <<'EOF' || true
# Useful shell functions
gclean() {
  git fetch --prune
  git branch --merged main | grep -v "^\*\|main\|master\|develop" | xargs -r git branch -d 2>/dev/null
  git gc --aggressive --prune=now
}
mkcd() { mkdir -p "$1" && cd "$1"; }
take() { mkdir -p -- "$1" && cd -- "$1"; }
EOF
  
  # Git delta configuration (run from $HOME so dev user cannot hit repo cwd)
  if cmd_exists delta; then
    sudo -u "$TARGET_USER" bash -c 'cd "$HOME" && git config --global core.pager "delta"'
    sudo -u "$TARGET_USER" bash -c 'cd "$HOME" && git config --global interactive.diffFilter "delta --color-only"'
    sudo -u "$TARGET_USER" bash -c 'cd "$HOME" && git config --global delta.navigate true'
    sudo -u "$TARGET_USER" bash -c 'cd "$HOME" && git config --global delta.light false'
    sudo -u "$TARGET_USER" bash -c 'cd "$HOME" && git config --global merge.conflictstyle "diff3"'
  fi
  
  append_if_missing "$bashrc" "# FZF shell integration" "$fzf_block"
  append_if_missing "$bashrc" "# Zoxide integration" "$zoxide_block"
  append_if_missing "$bashrc" "# Useful shell functions" "$functions_block"
}

apply_user_tweaks() {
  user_bash_history_tweaks
  user_ssh_keepalive_config
  add_common_aliases
  setup_shell_integrations
  if cmd_exists starship; then
    append_if_missing "${TARGET_HOME}/.bashrc" 'starship init bash' 'eval "$(starship init bash)"'
  fi
}

# =============================================================================
# CLEAN: Image Cleanup Functions
# =============================================================================

apt_cleanup() {
  log "APT cleanup"
  apt-get autoremove --purge -y || true
  apt-get clean || true
  rm -rf /var/lib/apt/lists/* || true
}

logs_cleanup() {
  if [[ "$KEEP_LOGS" -eq 1 ]]; then
    log "Skipping logs cleanup (--keep-logs)"
    return 0
  fi
  log "Vacuuming journald and truncating logs"
  if cmd_exists journalctl; then
    journalctl --rotate || true
    journalctl --vacuum-time=1s || true
  fi
  find /var/log -type f -exec truncate -s 0 {} \; || true
  find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete || true
}

machine_id_reset() {
  if [[ "$KEEP_MACHINE_ID" -eq 1 ]]; then
    log "Skipping machine-id reset (--keep-machine-id)"
    return 0
  fi
  log "Resetting machine-id"
  truncate -s 0 /etc/machine-id || true
  rm -f /var/lib/dbus/machine-id || true
  ln -sf /etc/machine-id /var/lib/dbus/machine-id || true
}

ssh_host_keys_cleanup() {
  if [[ "$KEEP_SSH_HOST_KEYS" -eq 1 ]]; then
    log "Skipping SSH host key removal (--keep-ssh-host-keys)"
    return 0
  fi
  log "Removing SSH host keys"
  rm -f /etc/ssh/ssh_host_* || true
}

cloud_init_cleanup() {
  if [[ "$DO_CLOUD_INIT_CLEAN" -ne 1 ]]; then
    return 0
  fi
  if cmd_exists cloud-init; then
    log "Running cloud-init clean"
    cloud-init clean --logs || cloud-init clean || true
    rm -rf /var/lib/cloud/instances/* || true
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
  rm -f /root/.bash_history /root/.zsh_history 2>/dev/null || true
  for d in /home/*; do
    [[ -d "$d" ]] || continue
    rm -f "$d/.bash_history" "$d/.zsh_history" 2>/dev/null || true
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

# =============================================================================
# Command Runners
# =============================================================================

do_dev() {
  log "=== Installing Development Tools ==="
  apt_update
  
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    apt_upgrade
  else
    install_core_packages
    if [[ "$DO_UPDATE" -eq 1 ]]; then
      apt_upgrade
    fi
  fi
  
  setup_git_lfs
  install_or_update_delta
  install_or_update_zoxide
  install_or_update_starship
  install_or_update_docker
  install_or_update_hashicorp
  install_or_update_awscli
  install_or_update_github_cli
  if [[ "$RESOLVED_PROFILE" == "desktop" ]]; then
    case "$(dpkg --print-architecture)" in
      amd64|arm64|armhf) install_or_update_vscode ;;
      *) warn "VS Code package is unavailable for this architecture; skipping" ;;
    esac
    if [[ "$(dpkg --print-architecture)" == "amd64" ]]; then
      install_or_update_chrome
    else
      warn "Google Chrome package is amd64-only here; skipping"
    fi
  fi
  
  success "Development tools installed"
}

do_env() {
  log "=== Configuring System Environment ==="
  
  enable_ntp
  set_inotify_limits
  set_ulimits
  disable_apport
  cap_journald
  ensure_pkg sudo
  if [[ "$APPLY_UK_SETTINGS" -eq 1 ]]; then
    set_uk_locale
  fi
  
  if [[ "$INSTALL_GUI" -eq 1 ]]; then
    install_ubuntu_desktop
  fi
  
  if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    create_dev_user
  fi
  
  if [[ "$RESOLVED_PROFILE" == "desktop" ]]; then
    install_nerd_fonts
    disable_browser_first_run
    if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
      install_dev_background
    fi
  fi
  
  if [[ "$DO_USER_TWEAKS" -eq 1 ]]; then
    log "Applying user tweaks for: $TARGET_USER"
    apply_user_tweaks
  fi

  ensure_ssh_client
  success "System environment configured"
}

do_clean() {
  log "=== Preparing System for Imaging ==="
  
  apt_cleanup
  logs_cleanup
  temp_cleanup
  user_history_cleanup
  user_cache_cleanup
  ssh_host_keys_cleanup
  machine_id_reset
  cloud_init_cleanup
  sync || true
  
  success "Image cleanup complete"
  log "Recommended: power off now and capture the image"
  
  if [[ "$NO_SHUTDOWN" -eq 1 ]]; then
    log "Skipping automatic shutdown (--no-shutdown)"
  else
    log "Shutting down in 10 sec... (Ctrl-C to abort)"
    sleep 10
    shutdown -h now
  fi
}

do_update() {
  UPDATE_ONLY=1
  DO_UPDATE=1
  do_dev
}

do_all() {
  if [[ -f "$SETUP_MARKER" ]] && [[ "$FORCE_RERUN" -eq 0 ]]; then
    if grep -Fxq "setup_schema=2" "$SETUP_MARKER" &&
       grep -Fxq "profile=$RESOLVED_PROFILE" "$SETUP_MARKER" &&
       grep -Fxq "requested_profile=$INSTALL_PROFILE" "$SETUP_MARKER" &&
       grep -Fxq "install_gui=$INSTALL_GUI" "$SETUP_MARKER" &&
       grep -Fxq "target=$TARGET_USER" "$SETUP_MARKER" &&
       grep -Fxq "create_dev=$CREATE_DEV_USER" "$SETUP_MARKER" &&
       grep -Fxq "ssh_server=$INSTALL_SSH_SERVER" "$SETUP_MARKER" &&
       grep -Fxq "uk_settings=$APPLY_UK_SETTINGS" "$SETUP_MARKER" &&
       grep -Fxq "user_tweaks=$DO_USER_TWEAKS" "$SETUP_MARKER" &&
       [[ "$DO_UPDATE" -eq 0 ]]; then
      log "Full setup already completed for this plan; refreshing Docker CE"
      install_or_update_docker
      if [[ "$REBOOT_AFTER" -eq 1 ]]; then
        log "Rebooting as requested"
        reboot
      fi
      return 0
    fi
    log "Existing setup marker differs from this plan; applying requested setup"
  fi
  
  do_dev
  echo ""
  do_env
  echo ""
  
  # Create marker file on successful completion
  {
    printf 'completed=%s\n' "$(date -Iseconds)"
    printf 'setup_schema=2\n'
    printf 'profile=%s\n' "$RESOLVED_PROFILE"
    printf 'requested_profile=%s\n' "$INSTALL_PROFILE"
    printf 'install_gui=%s\n' "$INSTALL_GUI"
    printf 'target=%s\n' "$TARGET_USER"
    printf 'create_dev=%s\n' "$CREATE_DEV_USER"
    printf 'ssh_server=%s\n' "$INSTALL_SSH_SERVER"
    printf 'uk_settings=%s\n' "$APPLY_UK_SETTINGS"
    printf 'user_tweaks=%s\n' "$DO_USER_TWEAKS"
  } > "$SETUP_MARKER"
  
  success "Full setup complete!"
  if [[ "$REBOOT_AFTER" -eq 1 ]]; then
    log "Rebooting to apply all changes"
    reboot
  else
    log "Reboot when convenient to apply desktop changes"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"
  validate_command_options
  resolve_install_profile
  resolve_target_user
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY RUN MODE - no changes will be made"
    show_plan
    exit 0
  fi
  
  check_root
  export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
  detect_distro
  
  log "Ubuntu Dev Box Setup"
  show_plan
  echo ""
  
  case "$COMMAND" in
    all)    do_all ;;
    dev)    do_dev ;;
    env)    do_env ;;
    clean)  do_clean ;;
    update) do_update ;;
    *)
      error "Unknown command: $COMMAND"
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
