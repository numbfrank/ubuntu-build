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
#   --no-dev-user     Do not create the 'dev' user
#   --gui             Install Ubuntu Desktop GUI (for headless VMs)
#
# By default, creates a 'dev' user with:
#   - Password: dev
#   - Passwordless sudo
#   - All aliases, SSH config, and shell integrations

DO_DESKTOP=1
DO_USER_TWEAKS=1
CREATE_DEV_USER=1
INSTALL_GUI=0
TARGET_USER="${SUDO_USER:-$USER}"

log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-desktop) DO_DESKTOP=0; shift ;;
      --no-user-tweaks) DO_USER_TWEAKS=0; shift ;;
      --no-dev-user) CREATE_DEV_USER=0; shift ;;
      --gui) INSTALL_GUI=1; shift ;;
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

# Helper: run gsettings as TARGET_USER with DBUS session
run_gsettings() {
  local schema="$1"
  local key="$2"
  local value="$3"
  local dbus_addr="unix:path=/run/user/$(id -u "$TARGET_USER")/bus"
  sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
    gsettings set "$schema" "$key" "$value" 2>/dev/null || true
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
    
    # Create user with home directory and bash shell
    useradd -m -s /bin/bash -G sudo,docker "$dev_user" 2>/dev/null || \
      useradd -m -s /bin/bash -G sudo "$dev_user"
    
    # Set a default password (user should change this)
    echo "${dev_user}:${dev_user}" | chpasswd
    
    log "User '$dev_user' created (password: '$dev_user')"
  fi
  
  # Configure passwordless sudo
  log "Configuring passwordless sudo for '$dev_user'"
  echo "${dev_user} ALL=(ALL) NOPASSWD:ALL" | tee "/etc/sudoers.d/90-${dev_user}-nopasswd" >/dev/null
  chmod 440 "/etc/sudoers.d/90-${dev_user}-nopasswd"
  
  # Validate sudoers syntax
  if ! visudo -c -f "/etc/sudoers.d/90-${dev_user}-nopasswd" >/dev/null 2>&1; then
    log "ERROR: Invalid sudoers syntax, removing file"
    rm -f "/etc/sudoers.d/90-${dev_user}-nopasswd"
    return 1
  fi
  
  # Copy SSH keys from TARGET_USER if they exist
  local source_ssh="/home/${TARGET_USER}/.ssh"
  local dest_ssh="${dev_home}/.ssh"
  
  if [[ -d "$source_ssh" ]] && [[ "$TARGET_USER" != "$dev_user" ]]; then
    log "Copying SSH keys from '$TARGET_USER' to '$dev_user'"
    cp -r "$source_ssh" "$dest_ssh" 2>/dev/null || true
    chown -R "${dev_user}:${dev_user}" "$dest_ssh" 2>/dev/null || true
    chmod 700 "$dest_ssh" 2>/dev/null || true
    chmod 600 "$dest_ssh"/* 2>/dev/null || true
  fi
  
  log "Dev user setup complete"
}

regenerate_ssh_host_keys() {
  log "Regenerating SSH host keys and certificates"
  
  # Remove old SSH host keys and certificates
  sudo rm -f /etc/ssh/ssh_host_*
  
  # Regenerate SSH host keys
  sudo ssh-keygen -A
  
  # Restart SSH service to use new keys
  sudo systemctl restart ssh || sudo systemctl restart sshd || true
  
  log "New SSH host keys generated"
}

setup_user_ssh_keys() {
  log "Setting up SSH keys for user: $TARGET_USER"
  
  local ssh_dir="/home/${TARGET_USER}/.ssh"
  local id_rsa="${ssh_dir}/id_rsa"
  local id_ed25519="${ssh_dir}/id_ed25519"
  
  # Create .ssh directory if it doesn't exist
  sudo -u "$TARGET_USER" mkdir -p "$ssh_dir"
  sudo -u "$TARGET_USER" chmod 700 "$ssh_dir"
  
  # Generate Ed25519 key if it doesn't exist (modern, recommended)
  if [[ ! -f "$id_ed25519" ]]; then
    log "Generating Ed25519 SSH key for $TARGET_USER"
    sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -f "$id_ed25519" -N "" -C "${TARGET_USER}@$(hostname)"
  fi
  
  # Generate RSA key if it doesn't exist (for compatibility)
  if [[ ! -f "$id_rsa" ]]; then
    log "Generating RSA SSH key for $TARGET_USER"
    sudo -u "$TARGET_USER" ssh-keygen -t rsa -b 4096 -f "$id_rsa" -N "" -C "${TARGET_USER}@$(hostname)"
  fi
}

configure_ssh_agent() {
  log "Configuring SSH agent for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local ssh_agent_block
  
  read -r -d '' ssh_agent_block <<'SSH_AGENT_EOF' || true
# SSH agent configuration
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
  ssh-add ~/.ssh/id_rsa 2>/dev/null || true
fi
SSH_AGENT_EOF
  
  append_if_missing "$bashrc" "# SSH agent configuration" "$ssh_agent_block"
  
  # Create SSH agent systemd user service for persistent agent
  local systemd_user_dir="/home/${TARGET_USER}/.config/systemd/user"
  sudo -u "$TARGET_USER" mkdir -p "$systemd_user_dir"
  
  sudo -u "$TARGET_USER" tee "${systemd_user_dir}/ssh-agent.service" >/dev/null <<'EOF'
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
EOF

  # Enable the SSH agent service
  sudo -u "$TARGET_USER" systemctl --user enable ssh-agent.service 2>/dev/null || true
  sudo -u "$TARGET_USER" systemctl --user start ssh-agent.service 2>/dev/null || true
  
  # Add environment variable for SSH_AUTH_SOCK
  local env_file="/home/${TARGET_USER}/.config/environment.d/ssh-agent.conf"
  sudo -u "$TARGET_USER" mkdir -p "/home/${TARGET_USER}/.config/environment.d"
  echo "SSH_AUTH_SOCK=\"\${XDG_RUNTIME_DIR}/ssh-agent.socket\"" | sudo -u "$TARGET_USER" tee "$env_file" >/dev/null
}

install_ubuntu_desktop() {
  log "Installing Ubuntu Desktop GUI"
  
  # Detect distro for appropriate desktop package
  # shellcheck disable=SC1091
  . /etc/os-release
  
  case "${ID:-}" in
    ubuntu)
      log "Installing ubuntu-desktop (this may take a while...)"
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop
      ;;
    debian)
      log "Installing Debian GNOME desktop (this may take a while...)"
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop
      ;;
    *)
      log "Unsupported distro for GUI install: ${ID:-unknown}"
      return 1
      ;;
  esac
  
  # Enable graphical target (boot to GUI)
  sudo systemctl set-default graphical.target
  
  # Enable GDM display manager
  if command -v gdm3 >/dev/null 2>&1; then
    sudo systemctl enable gdm3 || true
  elif command -v gdm >/dev/null 2>&1; then
    sudo systemctl enable gdm || true
  fi
  
  # Configure GDM to show dev user as default (no auto-login)
  log "Setting dev as default login user"
  sudo mkdir -p /var/lib/AccountsService/users
  sudo tee /var/lib/AccountsService/users/dev >/dev/null <<'EOF'
[User]
SystemAccount=false
EOF
  
  # Set dev as last logged in user (makes it the default selection)
  sudo mkdir -p /var/cache/gdm
  echo "dev" | sudo tee /var/cache/gdm/last-logged-in-user >/dev/null 2>&1 || true
  
  # Configure dock favorites for dev user
  log "Configuring dock favorites"
  local dock_favorites="['org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'code.desktop', 'google-chrome.desktop', 'firefox.desktop', 'org.gnome.Settings.desktop']"
  
  # Set for dev user
  sudo -u dev dbus-launch gsettings set org.gnome.shell favorite-apps "$dock_favorites" 2>/dev/null || true
  
  # Also create dconf override for all users
  sudo mkdir -p /etc/dconf/db/local.d
  sudo tee /etc/dconf/db/local.d/01-dock-favorites >/dev/null <<'EOF'
[org/gnome/shell]
favorite-apps=['org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'code.desktop', 'google-chrome.desktop', 'firefox.desktop', 'org.gnome.Settings.desktop']
EOF
  
  # Update dconf database
  sudo dconf update 2>/dev/null || true
  
  log "Ubuntu Desktop installed - reboot to start GUI (default user: dev)"
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

disable_screen_lock() {
  log "Disabling screen lock and auto-suspend for user: $TARGET_USER"
  
  # GNOME settings (if running GNOME)
  if command -v gsettings >/dev/null 2>&1; then
    run_gsettings org.gnome.desktop.screensaver lock-enabled false
    run_gsettings org.gnome.desktop.screensaver idle-activation-enabled false
    run_gsettings org.gnome.desktop.session idle-delay 0
    run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
    run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "'nothing'"
  fi
}

set_uk_locale() {
  log "Setting UK locale, keyboard, and timezone"
  
  # Install UK locale
  sudo apt-get install -y locales
  sudo locale-gen en_GB.UTF-8
  sudo update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8
  
  # Set timezone to London
  sudo timedatectl set-timezone Europe/London || true
  
  # Set keyboard to UK layout
  sudo tee /etc/default/keyboard >/dev/null <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
  sudo dpkg-reconfigure -f noninteractive keyboard-configuration || true
  
  # Update GNOME settings if available
  if command -v gsettings >/dev/null 2>&1; then
    run_gsettings org.gnome.desktop.input-sources sources "[('xkb', 'gb')]"
  fi
}

install_emoji_fonts() {
  log "Installing emoji font support"
  sudo apt-get install -y fonts-noto-color-emoji fonts-noto-emoji
  
  # Create fontconfig for emoji support
  sudo tee /etc/fonts/local.conf >/dev/null <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Color Emoji</family>
      <family>Noto Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Color Emoji</family>
      <family>Noto Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Noto Mono</family>
      <family>Noto Color Emoji</family>
      <family>Noto Emoji</family>
    </prefer>
  </alias>
</fontconfig>
EOF
  sudo fc-cache -f -v >/dev/null 2>&1 || true
}

disable_browser_first_run() {
  log "Disabling browser first-run prompts for user: $TARGET_USER"
  
  # Firefox preferences
  local firefox_profile_dir="/home/${TARGET_USER}/.mozilla/firefox"
  if [[ -d "$firefox_profile_dir" ]]; then
    # Find default profile or create preferences
    for profile in "$firefox_profile_dir"/*.default* "$firefox_profile_dir"/*.default-release*; do
      if [[ -d "$profile" ]]; then
        local user_js="$profile/user.js"
        sudo -u "$TARGET_USER" tee -a "$user_js" >/dev/null <<'EOF'
// Disable first-run prompts
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
EOF
        sudo chown "$TARGET_USER":"$TARGET_USER" "$user_js"
      fi
    done
  fi
  
  # Firefox policies (system-wide)
  sudo mkdir -p /etc/firefox/policies
  sudo tee /etc/firefox/policies/policies.json >/dev/null <<'EOF'
{
  "policies": {
    "DisableProfileImport": true,
    "DisableSetDesktopBackground": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": ""
  }
}
EOF

  # Chrome/Chromium preferences
  local chrome_prefs="/home/${TARGET_USER}/.config/google-chrome/Default/Preferences"
  local chromium_prefs="/home/${TARGET_USER}/.config/chromium/Default/Preferences"
  
  # Chrome master preferences (applied on first run)
  sudo mkdir -p /etc/opt/chrome/policies/managed
  sudo tee /etc/opt/chrome/policies/managed/no-first-run.json >/dev/null <<'EOF'
{
  "WelcomePageOnOSUpgradeEnabled": false,
  "ShowHomeButton": true,
  "RestoreOnStartup": 1,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false
}
EOF

  # Chromium policies
  sudo mkdir -p /etc/chromium/policies/managed
  sudo tee /etc/chromium/policies/managed/no-first-run.json >/dev/null <<'EOF'
{
  "WelcomePageOnOSUpgradeEnabled": false,
  "ShowHomeButton": true,
  "RestoreOnStartup": 1,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false
}
EOF

  # Edge policies
  sudo mkdir -p /etc/opt/edge/policies/managed
  sudo tee /etc/opt/edge/policies/managed/no-first-run.json >/dev/null <<'EOF'
{
  "HideFirstRunExperience": true,
  "WelcomePageOnOSUpgradeEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false
}
EOF

  # Set environment variable to disable first-run for Chrome/Chromium
  local env_file="/etc/environment"
  if ! grep -q "CHROME_FIRST_RUN" "$env_file" 2>/dev/null; then
    echo "CHROME_FIRST_RUN=0" | sudo tee -a "$env_file" >/dev/null
  fi
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
  read -r -d '' block <<'HISTORY_EOF' || true

# Dev box history defaults
shopt -s histappend
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a"
HISTSIZE=100000
HISTFILESIZE=200000
HISTORY_EOF
  append_if_missing "$bashrc" "# Dev box history defaults" "$block"
}

user_ssh_keepalive_config() {
  log "Applying SSH keepalive defaults for user: $TARGET_USER"
  local sshcfg="/home/${TARGET_USER}/.ssh/config"
  local block
  read -r -d '' block <<'SSH_EOF' || true

Host *
  ServerAliveInterval 60
  ServerAliveCountMax 5
SSH_EOF
  append_if_missing "$sshcfg" "ServerAliveInterval 60" "$block"
  sudo chmod 600 "$sshcfg" || true
  sudo chown "$TARGET_USER":"$TARGET_USER" "$sshcfg" || true
}

add_docker_tool_aliases() {
  log "Adding Docker tool aliases for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local zshrc="/home/${TARGET_USER}/.zshrc"
  
  local aliases_block
  read -r -d '' aliases_block <<'DOCKER_TOOLS_EOF' || true
# Docker-based development tool aliases
alias lazydocker='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v ~/.config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'
alias lazygit='docker run --rm -it -v "$PWD:/repo" -v ~/.gitconfig:/root/.gitconfig:ro -w /repo lazyteam/lazygit'
DOCKER_TOOLS_EOF
  
  # Add to .bashrc
  append_if_missing "$bashrc" "# Docker-based development tool aliases" "$aliases_block"
  
  # Add to .zshrc if it exists or user is using zsh
  if [[ -f "$zshrc" ]] || [[ "${SHELL##*/}" == "zsh" ]]; then
    append_if_missing "$zshrc" "# Docker-based development tool aliases" "$aliases_block"
  fi
}

add_common_aliases() {
  log "Adding common dev aliases for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local zshrc="/home/${TARGET_USER}/.zshrc"
  
  local aliases_block
  read -r -d '' aliases_block <<'ALIASES_EOF' || true
# Common dev aliases

# Docker shortcuts
alias docker-clean="docker system prune -af --volumes"
alias docker-stop-all="docker stop \$(docker ps -aq)"
alias dps="docker ps"
alias dpsa="docker ps -a"
alias di="docker images"
alias dlogs="docker logs -f"
alias dexec="docker exec -it"
alias dinspect="docker inspect"
alias dnetwork="docker network ls"
alias dvolume="docker volume ls"

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

# Git advanced - update current branch from main
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
alias ....="cd ../../.."

# System info
alias ports="netstat -tulanp"
alias listening="netstat -tlnp"
alias meminfo="free -h"
alias diskinfo="df -h"
alias cpuinfo="lscpu"
alias psg="ps aux | grep -v grep | grep -i -e VSZ -e"
alias myip="curl -s ifconfig.me"

# List aliases
alias ll="ls -lah"
alias la="ls -A"
alias l="ls -CF"
ALIASES_EOF
  
  # Add to .bashrc
  append_if_missing "$bashrc" "# Common dev aliases" "$aliases_block"
  
  # Add to .zshrc if it exists
  if [[ -f "$zshrc" ]] || [[ "${SHELL##*/}" == "zsh" ]]; then
    append_if_missing "$zshrc" "# Common dev aliases" "$aliases_block"
  fi
}

setup_shell_integrations() {
  log "Setting up shell integrations (fzf, zoxide, delta) for user: $TARGET_USER"
  
  local bashrc="/home/${TARGET_USER}/.bashrc"
  local zshrc="/home/${TARGET_USER}/.zshrc"
  
  # FZF integration
  local fzf_block
  read -r -d '' fzf_block <<'FZF_EOF' || true
# FZF shell integration
if command -v fzf >/dev/null 2>&1; then
  # FZF key bindings and fuzzy completion
  eval "$(fzf --bash)" 2>/dev/null || true
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
FZF_EOF
  
  # Zoxide integration
  local zoxide_block
  read -r -d '' zoxide_block <<'ZOXIDE_EOF' || true
# Zoxide integration
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
  alias cd="z"
fi
ZOXIDE_EOF
  
  local zoxide_zsh_block
  read -r -d '' zoxide_zsh_block <<'ZOXIDE_ZSH_EOF' || true
# Zoxide integration
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
  alias cd="z"
fi
ZOXIDE_ZSH_EOF
  
  # Shell functions
  local functions_block
  read -r -d '' functions_block <<'FUNCTIONS_EOF' || true
# Useful shell functions

# Git cleanup - remove merged branches and stale objects
gclean() {
  echo "Cleaning up Git repository..."
  # Fetch and prune remote tracking branches
  git fetch --prune
  # Remove local branches that have been merged to main
  git branch --merged main | grep -v "^\*\|main\|master\|develop" | xargs -r git branch -d 2>/dev/null
  # Clean up unreachable objects
  git gc --aggressive --prune=now
  echo "Git cleanup complete!"
}

# Make directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract any archive
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"     ;;
      *.tar.gz)    tar xzf "$1"     ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar x "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xf "$1"      ;;
      *.tbz2)      tar xjf "$1"     ;;
      *.tgz)       tar xzf "$1"     ;;
      *.zip)       unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *)           echo "Cannot extract $1" ;;
    esac
  else
    echo "$1 is not a valid file"
  fi
}

# Quick backup of a file
backup() {
  cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
}
FUNCTIONS_EOF
  
  # Git delta configuration
  local gitconfig="/home/${TARGET_USER}/.gitconfig"
  if command -v delta >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" git config --global core.pager "delta"
    sudo -u "$TARGET_USER" git config --global interactive.diffFilter "delta --color-only"
    sudo -u "$TARGET_USER" git config --global delta.navigate true
    sudo -u "$TARGET_USER" git config --global delta.light false
    sudo -u "$TARGET_USER" git config --global delta.side-by-side false
    sudo -u "$TARGET_USER" git config --global merge.conflictstyle "diff3"
    sudo -u "$TARGET_USER" git config --global diff.colorMoved "default"
  fi
  
  # Add to .bashrc
  append_if_missing "$bashrc" "# FZF shell integration" "$fzf_block"
  append_if_missing "$bashrc" "# Zoxide integration" "$zoxide_block"
  append_if_missing "$bashrc" "# Useful shell functions" "$functions_block"
  
  # Add to .zshrc if it exists
  if [[ -f "$zshrc" ]] || [[ "${SHELL##*/}" == "zsh" ]]; then
    # ZSH uses different fzf init
    local fzf_zsh_block
    read -r -d '' fzf_zsh_block <<'FZF_ZSH_EOF' || true
# FZF shell integration
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh) 2>/dev/null || true
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
FZF_ZSH_EOF
    append_if_missing "$zshrc" "# FZF shell integration" "$fzf_zsh_block"
    append_if_missing "$zshrc" "# Zoxide integration" "$zoxide_zsh_block"
    append_if_missing "$zshrc" "# Useful shell functions" "$functions_block"
  fi
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
  regenerate_ssh_host_keys
  set_uk_locale
  install_emoji_fonts

  # Install Ubuntu Desktop GUI if requested
  if [[ "$INSTALL_GUI" -eq 1 ]]; then
    install_ubuntu_desktop
  fi

  # Create dev user (enabled by default)
  if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    create_dev_user
  fi

  if [[ "$DO_DESKTOP" -eq 1 ]]; then
    disable_lid_close_suspend
    disable_screen_lock
    disable_browser_first_run
  fi

  if [[ "$DO_USER_TWEAKS" -eq 1 ]]; then
    # Apply tweaks to invoking user
    log "Applying user tweaks for: $TARGET_USER"
    user_bash_history_tweaks
    user_ssh_keepalive_config
    setup_user_ssh_keys
    configure_ssh_agent
    add_docker_tool_aliases
    add_common_aliases
    setup_shell_integrations
    
    # Also apply tweaks to dev user if created
    if [[ "$CREATE_DEV_USER" -eq 1 ]] && [[ "$TARGET_USER" != "dev" ]]; then
      log "Applying user tweaks for: dev"
      TARGET_USER="dev"
      user_bash_history_tweaks
      user_ssh_keepalive_config
      setup_user_ssh_keys
      configure_ssh_agent
      add_docker_tool_aliases
      add_common_aliases
      setup_shell_integrations
    fi
  fi

  log "Done"
  if [[ "$CREATE_DEV_USER" -eq 1 ]]; then
    log "Dev user created - login: dev / password: dev"
  fi
}

main "$@"
