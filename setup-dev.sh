#!/usr/bin/env bash
set -euo pipefail

# Modern dev shell bootstrap (Ubuntu / Debian)
#
# Default (no flags): install everything.
# Modes:
#   --update        Install + update (post-upgrade refresh)
#   --update-only   Pure update mode (no installs; only updates what is present)
#
# Includes:
# - Bash + Starship
# - VS Code + vim
# - tmux
# - Docker Engine + Compose (apt)
# - Terraform + Packer
# - AWS CLI v2
# - Python 3 tooling
# - QoL: git, git-lfs, jq, ripgrep, fd, bat

TARGET_USER="${SUDO_USER:-$USER}"
DO_UPDATE=0
UPDATE_ONLY=0

log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --update) DO_UPDATE=1; shift ;;
      --update-only) UPDATE_ONLY=1; DO_UPDATE=1; shift ;;
      -h|--help)
        sed -n '1,140p' "$0"
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
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ;;
    *) echo "Unsupported distro: $ID" >&2; exit 1 ;;
  esac
  DIST_ID="$ID"
  DIST_CODENAME="$VERSION_CODENAME"
}

apt_update() {
  sudo apt-get update -y
}

apt_upgrade() {
  log "Upgrading system packages"
  sudo apt-get upgrade -y
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Helper: safely add GPG key (avoids overwriting existing)
add_gpg_key() {
  local url="$1"
  local keyring="$2"
  if [[ ! -f "$keyring" ]]; then
    curl -fsSL "$url" | sudo gpg --dearmor --yes -o "$keyring"
    sudo chmod a+r "$keyring"
  fi
}

# Helper: add apt repository
add_apt_repo() {
  local list_file="$1"
  local repo_line="$2"
  if [[ ! -f "$list_file" ]]; then
    echo "$repo_line" | sudo tee "$list_file" >/dev/null
  fi
}

install_core_packages() {
  log "Installing core dev packages"
  sudo apt-get install -y \
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

  sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
  sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
}

setup_git_lfs() {
  if cmd_exists git && cmd_exists git-lfs; then
    git lfs install --system >/dev/null 2>&1 || sudo git lfs install --system
  fi
}

install_or_update_delta() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists delta; then
    log "git-delta not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating git-delta"
  local version="0.17.0"
  local arch="amd64"
  local deb_url="https://github.com/dandavison/delta/releases/download/${version}/git-delta_${version}_${arch}.deb"
  local tmp_deb="/tmp/git-delta.deb"
  
  curl -fsSL "$deb_url" -o "$tmp_deb"
  sudo dpkg -i "$tmp_deb" || sudo apt-get install -f -y
  rm -f "$tmp_deb"
}

install_or_update_zoxide() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists zoxide; then
    log "zoxide not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating zoxide"
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sudo sh
}

ensure_hashicorp_repo() {
  add_gpg_key "https://apt.releases.hashicorp.com/gpg" "/usr/share/keyrings/hashicorp.gpg"
  add_apt_repo "/etc/apt/sources.list.d/hashicorp.list" \
    "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${DIST_CODENAME} main"
}

ensure_docker_repo() {
  sudo install -m 0755 -d /etc/apt/keyrings
  add_gpg_key "https://download.docker.com/linux/${DIST_ID}/gpg" "/etc/apt/keyrings/docker.gpg"
  add_apt_repo "/etc/apt/sources.list.d/docker.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DIST_ID} ${DIST_CODENAME} stable"
}

ensure_vscode_repo() {
  add_gpg_key "https://packages.microsoft.com/keys/microsoft.asc" "/usr/share/keyrings/vscode.gpg"
  add_apt_repo "/etc/apt/sources.list.d/vscode.list" \
    "deb [signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main"
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
  curl -fsSL https://starship.rs/install.sh | sudo sh -s -- -y

  local bashrc="/home/${TARGET_USER}/.bashrc"
  if [[ -f "$bashrc" ]] && ! grep -q "starship init bash" "$bashrc"; then
    echo 'eval "$(starship init bash)"' | sudo tee -a "$bashrc" >/dev/null
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
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker || true
    return 0
  fi

  log "Installing Docker"
  sudo apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
  ensure_docker_repo
  apt_update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
  sudo groupadd -f docker
  sudo usermod -aG docker "$TARGET_USER"
}

install_or_update_hashicorp() {
  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    if ! pkg_installed terraform && ! pkg_installed packer; then
      log "Terraform/Packer not installed; skipping (update-only mode)"
      return 0
    fi
    log "Updating Terraform and Packer"
    ensure_hashicorp_repo
    apt_update
    sudo apt-get install -y terraform packer
    return 0
  fi

  log "Installing Terraform and Packer"
  ensure_hashicorp_repo
  apt_update
  sudo apt-get install -y terraform packer
}

install_or_update_awscli() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! cmd_exists aws; then
    log "AWS CLI not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating AWS CLI v2"
  tmp="$(mktemp -d)"
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$tmp/aws.zip"
  unzip -q "$tmp/aws.zip" -d "$tmp"
  sudo "$tmp/aws/install" --update
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
  sudo apt-get install -y code
}

install_or_update_github_cli() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed gh; then
    log "GitHub CLI not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating GitHub CLI"
  ensure_github_cli_repo
  apt_update
  sudo apt-get install -y gh
}

install_or_update_chrome() {
  if [[ "$UPDATE_ONLY" -eq 1 ]] && ! pkg_installed google-chrome-stable; then
    log "Google Chrome not installed; skipping (update-only mode)"
    return 0
  fi

  log "Installing or updating Google Chrome"
  ensure_chrome_repo
  apt_update
  sudo apt-get install -y google-chrome-stable
}

do_install_all() {
  apt_update
  install_core_packages
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
}

do_update_only() {
  apt_update
  apt_upgrade
  install_or_update_delta
  install_or_update_zoxide
  install_or_update_starship
  install_or_update_docker
  install_or_update_hashicorp
  install_or_update_awscli
  install_or_update_vscode
  install_or_update_github_cli
  install_or_update_chrome
  setup_git_lfs
}

main() {
  parse_args "$@"
  detect_distro

  log "Distro: ${DIST_ID} (${DIST_CODENAME})"
  log "Target user: ${TARGET_USER}"

  if [[ "$UPDATE_ONLY" -eq 1 ]]; then
    do_update_only
    log "Update-only complete"
    exit 0
  fi

  do_install_all

  if [[ "$DO_UPDATE" -eq 1 ]]; then
    do_update_only
  fi

  log "Setup complete (re-login required for Docker group membership changes)"
}

main "$@"
 
