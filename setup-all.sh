#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Ubuntu Dev Box Setup - All-in-One Script
# =============================================================================
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/setup-all.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- [command] [options]
#
# Commands:
#   all          Run dev + env setup (default)
#   dev          Install development tools only
#   env          Apply system/user configuration only
#   clean        Prepare system for imaging
#   update       Update all installed tools
#
# Options:
#   --console          Console/WSL only: no GUI, skip desktop settings (default for WSL)
#   --gui              Install Ubuntu Desktop GUI
#   --force, -f        Force re-run even if already completed
#   --no-desktop       Skip desktop-specific settings
#   --no-user-tweaks   Skip per-user configurations
#   --current-user     Apply config to current user only (do not create dev user)
#   --dev-user         Create dev user and apply config to dev only
#   --user NAME        Apply config to NAME only (create dev only if NAME is 'dev')
#   --no-dev-user      Don't create the 'dev' user (same as --current-user)
#   --no-shutdown      Don't shutdown after clean (for clean command)
#   --dry-run          Show what would run without executing
#   -h, --help         Show this help message
#
# Creates 'dev' user by default:
#   - Username: dev
#   - Password: dev (CHANGE THIS!)
#   - Passwordless sudo
#
# Examples:
#   curl ... | sudo bash                    # Full setup (creates dev + applies to both)
#   curl ... | sudo bash -s -- --console   # Explicit console/WSL setup (no GUI)
#   curl ... | sudo bash -s -- --current-user  # Set up current user only (no dev user)
#   curl ... | sudo bash -s -- --dev-user  # Create dev user, apply to dev only
#   curl ... | sudo bash -s -- --gui       # Full setup with desktop GUI
#   curl ... | sudo bash -s -- dev         # Dev tools only

# =============================================================================
# Configuration
# =============================================================================

COMMAND="all"
DRY_RUN=0
DO_UPDATE=0
UPDATE_ONLY=0
DO_DESKTOP=1
DO_USER_TWEAKS=1
CREATE_DEV_USER=1
INSTALL_GUI=0
NO_SHUTDOWN=0
FORCE_RERUN=0
TARGET_USER="${SUDO_USER:-$USER}"

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
  sed -n '3,40p' "$0" | sed 's/^# \?//'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      all|dev|env|clean|update)
        COMMAND="$1"
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
      --gui)
        INSTALL_GUI=1
        shift
        ;;
      --console)
        INSTALL_GUI=0
        DO_DESKTOP=0
        shift
        ;;
      --no-desktop)
        DO_DESKTOP=0
        shift
        ;;
      --no-user-tweaks)
        DO_USER_TWEAKS=0
        shift
        ;;
      --current-user)
        CREATE_DEV_USER=0
        TARGET_USER="${SUDO_USER:-$USER}"
        shift
        ;;
      --dev-user)
        CREATE_DEV_USER=1
        TARGET_USER="dev"
        shift
        ;;
      --no-dev-user)
        CREATE_DEV_USER=0
        shift
        ;;
      --force|-f)
        FORCE_RERUN=1
        shift
        ;;
      --user)
        TARGET_USER="$2"
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
      ;;
    *)
      error "Unsupported OS: ${ID:-unknown}. Supports Ubuntu/Debian only."
      exit 1
      ;;
  esac
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
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
  if [[ ! -f "$list_file" ]]; then
    echo "$repo_line" | tee "$list_file" >/dev/null
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
  touch "$file"
  chown "$TARGET_USER":"$TARGET_USER" "$file" || true

  if ! grep -qF "$needle" "$file" 2>/dev/null; then
    printf "\n%s\n" "$block" | tee -a "$file" >/dev/null
    chown "$TARGET_USER":"$TARGET_USER" "$file" || true
  fi
}

# =============================================================================
# DEV: Installation Functions
# =============================================================================

apt_update() {
  apt-get update -y
}

apt_dist_upgrade() {
  log "Performing full system upgrade (dist-upgrade)"
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
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
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists delta; then
    log "git-delta not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating git-delta"
  local version="0.17.0"
  local deb_url="https://github.com/dandavison/delta/releases/download/${version}/git-delta_${version}_amd64.deb"
  local tmp_deb="/tmp/git-delta.deb"
  
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
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
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
  # Remove any existing conflicting VS Code repo configs (both .list and .sources formats)
  rm -f /etc/apt/sources.list.d/vscode*.list 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/vscode*.sources 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/microsoft*.list 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/microsoft*.sources 2>/dev/null || true
  rm -f /usr/share/keyrings/microsoft.gpg 2>/dev/null || true
  
  add_gpg_key "https://packages.microsoft.com/keys/microsoft.asc" "/usr/share/keyrings/vscode.gpg"
  add_apt_repo "/etc/apt/sources.list.d/vscode.list" \
    "deb [signed-by=/usr/share/keyrings/vscode.gpg arch=amd64] https://packages.microsoft.com/repos/code stable main"
}

ensure_github_cli_repo() {
  add_gpg_key "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "/usr/share/keyrings/githubcli-archive-keyring.gpg"
  add_apt_repo "/etc/apt/sources.list.d/github-cli.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
}

ensure_chrome_repo() {
  add_gpg_key "https://dl.google.com/linux/linux_signing_key.pub" "/usr/share/keyrings/google-chrome.gpg"
  add_apt_repo "/etc/apt/sources.list.d/google-chrome.list" \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main"
}

install_or_update_starship() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists starship; then
    log "Starship not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating Starship"
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y

  # Add to TARGET_USER's bashrc
  local bashrc="/home/${TARGET_USER}/.bashrc"
  if [[ -f "$bashrc" ]] && ! grep -q "starship init bash" "$bashrc"; then
    echo 'eval "$(starship init bash)"' | tee -a "$bashrc" >/dev/null
  fi
  
  # Also add to dev user's bashrc if different
  if [[ "$TARGET_USER" != "dev" ]] && [[ -d "/home/dev" ]]; then
    local dev_bashrc="/home/dev/.bashrc"
    if [[ -f "$dev_bashrc" ]] && ! grep -q "starship init bash" "$dev_bashrc"; then
      echo 'eval "$(starship init bash)"' | tee -a "$dev_bashrc" >/dev/null
      chown dev:dev "$dev_bashrc" || true
    fi
  fi
}

install_or_update_docker() {
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    if ! pkg_installed docker-ce && ! pkg_installed docker.io; then
      log "Docker not installed; skipping (update-only mode)"
      return 0
    fi
    log "Updating Docker"
    ensure_docker_repo
    apt_update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker || true
    return 0
  fi

  log "Installing Docker"
  apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
  ensure_docker_repo
  apt_update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  groupadd -f docker
  usermod -aG docker "$TARGET_USER"
  # Also add dev user to docker group if it exists
  id dev &>/dev/null && usermod -aG docker dev || true
}

install_or_update_hashicorp() {
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    if ! pkg_installed terraform && ! pkg_installed packer; then
      log "Terraform/Packer not installed; skipping (update-only mode)"
      return 0
    fi
  fi

  log "Installing Terraform and Packer"
  ensure_hashicorp_repo
  apt_update
  apt-get install -y terraform packer
}

install_or_update_awscli() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists aws; then
    log "AWS CLI not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating AWS CLI v2"
  local tmp="$(mktemp -d)"
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$tmp/aws.zip"
  unzip -q "$tmp/aws.zip" -d "$tmp"
  "$tmp/aws/install" --update || true
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
  log "Ensuring OpenSSH client and server are installed"
  ensure_pkg openssh-client
  ensure_pkg openssh-server
}

create_dev_user() {
  local dev_user="dev"
  local dev_home="/home/${dev_user}"
  
  if id "$dev_user" &>/dev/null; then
    log "User '$dev_user' already exists"
  else
    log "Creating user '$dev_user' with passwordless sudo"
    useradd -m -s /bin/bash -G sudo "$dev_user" 2>/dev/null || useradd -m -s /bin/bash "$dev_user"
    usermod -aG sudo "$dev_user" || true
    echo "${dev_user}:${dev_user}" | chpasswd
    log "User '$dev_user' created (password: '$dev_user')"
  fi
  
  # Add to docker group if it exists
  getent group docker >/dev/null && usermod -aG docker "$dev_user" || true
  
  # Configure passwordless sudo
  log "Configuring passwordless sudo for '$dev_user'"
  echo "${dev_user} ALL=(ALL) NOPASSWD:ALL" | tee "/etc/sudoers.d/90-${dev_user}-nopasswd" >/dev/null
  chmod 440 "/etc/sudoers.d/90-${dev_user}-nopasswd"
  
  if ! visudo -c -f "/etc/sudoers.d/90-${dev_user}-nopasswd" >/dev/null 2>&1; then
    log "ERROR: Invalid sudoers syntax, removing file"
    rm -f "/etc/sudoers.d/90-${dev_user}-nopasswd"
    return 1
  fi
  
  log "Dev user setup complete"
}

regenerate_ssh_host_keys() {
  # Only regenerate on first run to avoid breaking existing SSH connections
  if [[ -f "$SETUP_MARKER" ]] && [[ "$FORCE_RERUN" -eq 0 ]]; then
    log "Skipping SSH host key regeneration (already configured)"
    return 0
  fi
  
  log "Regenerating SSH host keys"
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A
  systemctl restart ssh || systemctl restart sshd || true
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
  
  if cmd_exists gsettings; then
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

install_ubuntu_desktop() {
  log "Installing Ubuntu Desktop GUI"
  
  case "${DIST_ID}" in
    ubuntu)
      log "Installing ubuntu-desktop (this may take a while...)"
      DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop
      ;;
    debian)
      log "Installing Debian GNOME desktop (this may take a while...)"
      DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop
      ;;
  esac
  
  systemctl set-default graphical.target
  
  if cmd_exists gdm3; then
    systemctl enable gdm3 || true
  elif cmd_exists gdm; then
    systemctl enable gdm || true
  fi
  
  # Set dev as default login user
  log "Setting dev as default login user"
  mkdir -p /var/lib/AccountsService/users
  tee /var/lib/AccountsService/users/dev >/dev/null <<'EOF'
[User]
SystemAccount=false
EOF
  mkdir -p /var/cache/gdm
  echo "dev" | tee /var/cache/gdm/last-logged-in-user >/dev/null 2>&1 || true
  
  # Configure dock favorites and disable welcome screen
  log "Configuring dock favorites and GNOME defaults"
  mkdir -p /etc/dconf/db/local.d
  mkdir -p /etc/dconf/db/local.d/locks
  mkdir -p /etc/dconf/profile
  
  # Create dconf profile - must be named 'user' and loaded by gdm
  tee /etc/dconf/profile/user >/dev/null <<'EOF'
user-db:user
system-db:local
EOF

  # Also create gdm profile for login screen
  tee /etc/dconf/profile/gdm >/dev/null <<'EOF'
user-db:user
system-db:gdm
system-db:local
EOF
  
  # Set dock favorites and disable welcome
  tee /etc/dconf/db/local.d/01-devbox-defaults >/dev/null <<'EOF'
[org/gnome/shell]
favorite-apps=['org.gnome.Terminal.desktop', 'code.desktop', 'org.gnome.TextEditor.desktop', 'google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']
welcome-dialog-last-shown-version='99.0'

[org/gnome/shell/extensions/dash-to-dock]
dash-max-icon-size=48
dock-fixed=true
dock-position='LEFT'

[org/gnome/desktop/notifications/application/org-gnome-welcome]
enable=false

[org/gnome/shell/extensions/ding]
show-home=false
EOF

  # Lock the favorite-apps so system default is used
  tee /etc/dconf/db/local.d/locks/01-devbox-locks >/dev/null <<'EOF'
/org/gnome/shell/favorite-apps
/org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size
EOF
  
  dconf update 2>/dev/null || true
  
  # Disable gnome-initial-setup and gnome-tour completely
  log "Removing GNOME initial setup / welcome screen packages"
  
  # Remove the packages entirely - most reliable method
  apt-get remove --autoremove -y gnome-initial-setup gnome-tour 2>/dev/null || true
  
  # Also mark as done for any reinstall via skel
  mkdir -p /etc/skel/.config
  echo "yes" | tee /etc/skel/.config/gnome-initial-setup-done >/dev/null
  
  # Mask the systemd user services as backup
  systemctl --global mask gnome-initial-setup-first-login.service 2>/dev/null || true
  systemctl --global mask gnome-initial-setup.service 2>/dev/null || true
  systemctl --global mask gnome-tour.service 2>/dev/null || true
  
  # Method 3: Remove the autostart entries
  rm -f /etc/xdg/autostart/gnome-initial-setup*.desktop 2>/dev/null || true
  rm -f /etc/xdg/autostart/gnome-tour*.desktop 2>/dev/null || true
  rm -f /etc/xdg/autostart/ubuntu-first-run*.desktop 2>/dev/null || true
  
  # Method 4: Mark gnome-initial-setup done in skel (for new users)
  # Dev user specific setup happens later in apply_dev_user_desktop_settings
  
  log "Ubuntu Desktop installed - reboot to start GUI"
}

apply_dev_user_desktop_settings() {
  # This runs AFTER dev user is created
  if ! id dev &>/dev/null; then
    return 0
  fi
  
  log "Applying desktop settings for dev user"
  
  # Mark gnome-initial-setup as done
  mkdir -p /home/dev/.config
  echo "yes" | tee /home/dev/.config/gnome-initial-setup-done >/dev/null
  
  # Download wallpaper
  mkdir -p /home/dev/Pictures
  curl -fsSL "$REPO_RAW_URL/files/dev-background.png" -o /home/dev/Pictures/dev-background.png || true
  
  # Create autostart script that runs on first login to set dock favorites
  # This is the most reliable approach because gsettings needs a running session
  mkdir -p /home/dev/.config/autostart
  tee /home/dev/.config/autostart/dev-setup-dock.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Dev Setup Dock Favorites
Exec=/home/dev/.config/autostart/dev-setup-dock.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

  tee /home/dev/.config/autostart/dev-setup-dock.sh >/dev/null <<'SCRIPT'
#!/bin/bash
# One-time desktop setup - runs on first login then deletes itself

# Set dock favorites
gsettings set org.gnome.shell favorite-apps \
  "['org.gnome.Terminal.desktop', 'code.desktop', 'org.gnome.TextEditor.desktop', 'google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"

# Disable welcome dialog
gsettings set org.gnome.shell welcome-dialog-last-shown-version '99.0'

# Set wallpaper
if [[ -f /home/dev/Pictures/dev-background.png ]]; then
  gsettings set org.gnome.desktop.background picture-uri "file:///home/dev/Pictures/dev-background.png"
  gsettings set org.gnome.desktop.background picture-uri-dark "file:///home/dev/Pictures/dev-background.png"
  gsettings set org.gnome.desktop.background picture-options 'zoom'
fi

# Configure terminal font (Hack Nerd Font, size 11)
PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
if [[ -n "$PROFILE" ]]; then
  gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/ font 'Hack Nerd Font Mono 11'
  gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/ use-system-font false
  gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/ audible-bell false
  gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/ bell-mode 'visual'
fi

# Disable screen lock and power settings
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true

# Self-destruct - remove autostart files after running
rm -f /home/dev/.config/autostart/dev-setup-dock.desktop
rm -f /home/dev/.config/autostart/dev-setup-dock.sh
SCRIPT

  chmod +x /home/dev/.config/autostart/dev-setup-dock.sh
  
  # Fix ownership
  chown -R dev:dev /home/dev/.config
  
  log "Dev user desktop settings will be applied on first login"
}

disable_lid_close_suspend() {
  log "Disabling lid-close suspend"
  mkdir -p /etc/systemd/logind.conf.d
  tee /etc/systemd/logind.conf.d/99-dev.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
EOF
  systemctl restart systemd-logind || true
}

disable_screen_lock() {
  log "Disabling screen lock for user: $TARGET_USER"
  if cmd_exists gsettings; then
    run_gsettings org.gnome.desktop.screensaver lock-enabled false
    run_gsettings org.gnome.desktop.screensaver idle-activation-enabled false
    run_gsettings org.gnome.desktop.session idle-delay 0
    run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
  fi
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

setup_user_ssh_keys() {
  log "Setting up SSH keys for user: $TARGET_USER"
  
  local ssh_dir="/home/${TARGET_USER}/.ssh"
  sudo -u "$TARGET_USER" mkdir -p "$ssh_dir"
  sudo -u "$TARGET_USER" chmod 700 "$ssh_dir"
  
  if [[ ! -f "${ssh_dir}/id_ed25519" ]]; then
    sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -f "${ssh_dir}/id_ed25519" -N "" -C "${TARGET_USER}@$(hostname)"
  fi
  
  if [[ ! -f "${ssh_dir}/id_rsa" ]]; then
    sudo -u "$TARGET_USER" ssh-keygen -t rsa -b 4096 -f "${ssh_dir}/id_rsa" -N "" -C "${TARGET_USER}@$(hostname)"
  fi
}

configure_ssh_agent() {
  log "Configuring SSH agent for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local ssh_agent_block
  read -r -d '' ssh_agent_block <<'EOF' || true
# SSH agent configuration
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
  ssh-add ~/.ssh/id_rsa 2>/dev/null || true
fi
EOF
  
  append_if_missing "$bashrc" "# SSH agent configuration" "$ssh_agent_block"
}

user_bash_history_tweaks() {
  log "Applying Bash history tweaks for user: $TARGET_USER"
  local bashrc="/home/${TARGET_USER}/.bashrc"
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
  local sshcfg="/home/${TARGET_USER}/.ssh/config"
  local block
  read -r -d '' block <<'EOF' || true
Host *
  ServerAliveInterval 60
  ServerAliveCountMax 5
EOF
  append_if_missing "$sshcfg" "ServerAliveInterval 60" "$block"
  chmod 600 "$sshcfg" || true
  chown "$TARGET_USER":"$TARGET_USER" "$sshcfg" || true
}

add_common_aliases() {
  log "Adding common dev aliases for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local aliases_block
  read -r -d '' aliases_block <<'EOF' || true
# Common dev aliases

# Docker shortcuts
alias docker-clean="docker system prune -af --volumes"
alias docker-stop-all="docker stop \$(docker ps -aq)"
alias dps="docker ps"
alias dpsa="docker ps -a"
alias di="docker images"
alias dlogs="docker logs -f"
alias dexec="docker exec -it"

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

# Docker tools
alias lazydocker='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v ~/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'
alias lazygit='docker run --rm -it -v "$PWD:/repo" -v ~/.gitconfig:/root/.gitconfig:ro -w /repo lazyteam/lazygit'
EOF
  
  append_if_missing "$bashrc" "# Common dev aliases" "$aliases_block"
}

setup_shell_integrations() {
  log "Setting up shell integrations for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  
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
  setup_user_ssh_keys
  configure_ssh_agent
  add_common_aliases
  setup_shell_integrations
}

# =============================================================================
# CLEAN: Image Cleanup Functions
# =============================================================================

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
  apt_dist_upgrade
  
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    apt_upgrade
  else
    install_core_packages
  fi
  
  setup_git_lfs
  install_or_update_delta
  install_or_update_zoxide
  install_or_update_starship
  install_or_update_docker
  install_or_update_hashicorp
  install_or_update_awscli
  install_or_update_vscode
  install_or_update_github_cli
  install_or_update_chrome
  
  success "Development tools installed"
}

do_env() {
  log "=== Configuring System Environment ==="
  
  enable_ntp
  set_inotify_limits
  set_ulimits
  disable_apport
  cap_journald
  ensure_ssh_client
  regenerate_ssh_host_keys
  set_uk_locale
  install_nerd_fonts
  
  # Auto-detect if desktop is already installed
  local has_desktop=0
  if pkg_installed ubuntu-desktop || pkg_installed gnome-shell || pkg_installed task-gnome-desktop; then
    has_desktop=1
    log "Desktop environment detected"
  fi
  
  if [[ "$INSTALL_GUI" -eq 1 ]]; then
    install_ubuntu_desktop
    has_desktop=1
  fi
  
  if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    create_dev_user
  fi
  
  # Apply desktop settings for dev user AFTER user is created
  # Run if --gui passed OR if desktop was auto-detected
  if [[ "$has_desktop" -eq 1 ]] && [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    apply_dev_user_desktop_settings
  fi
  
  # Apply desktop tweaks if desktop exists (--gui or auto-detected)
  if [[ "$has_desktop" -eq 1 ]] && [[ "$DO_DESKTOP" -eq 1 ]]; then
    # Remove gnome-initial-setup
    apt-get remove --autoremove -y gnome-initial-setup gnome-tour 2>/dev/null || true
    
    disable_lid_close_suspend
    disable_screen_lock
    disable_browser_first_run
  fi
  
  if [[ "$DO_USER_TWEAKS" -eq 1 ]]; then
    log "Applying user tweaks for: $TARGET_USER"
    apply_user_tweaks
    
    if [[ "$CREATE_DEV_USER" -eq 1 ]] && [[ "$TARGET_USER" != "dev" ]]; then
      log "Applying user tweaks for: dev"
      TARGET_USER="dev"
      apply_user_tweaks
    fi
  fi
  
  success "System environment configured"
  if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    log "Dev user created - login: dev / password: dev"
    warn "⚠️  IMPORTANT: Change the password! Run: sudo passwd dev"
  fi
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
  # Detect re-run
  if [[ -f "$SETUP_MARKER" ]] && [[ "$FORCE_RERUN" -eq 0 ]]; then
    warn "Setup has already been run on this system"
    log "Marker file: $SETUP_MARKER"
    echo ""
    log "Options:"
    log "  - Run 'update' command to update installed tools"
    log "  - Use --force to re-run full setup (may regenerate SSH keys)"
    log "  - Delete $SETUP_MARKER to reset"
    echo ""
    read -rp "Continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      log "Aborted"
      exit 0
    fi
  fi
  
  do_dev
  echo ""
  do_env
  echo ""
  
  # Create marker file on successful completion
  echo "Setup completed: $(date -Iseconds)" | tee "$SETUP_MARKER" >/dev/null
  
  success "Full setup complete!"
  log "System will reboot in 10 seconds to apply all changes..."
  log "(Press Ctrl+C to cancel)"
  sleep 10
  reboot
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY RUN MODE - would execute: $COMMAND"
    exit 0
  fi
  
  check_root
  detect_distro
  
  log "Ubuntu Dev Box Setup"
  log "Command: $COMMAND"
  log "Target user: $TARGET_USER"
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

main "$@"
