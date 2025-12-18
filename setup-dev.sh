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

ensure_hashicorp_repo() {
  if [[ ! -f /etc/apt/sources.list.d/hashicorp.list ]]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg

    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${DIST_CODENAME} main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  fi
}

ensure_docker_repo() {
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${DIST_ID}/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DIST_ID} ${DIST_CODENAME} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi
}

ensure_vscode_repo() {
  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | sudo gpg --dearmor -o /usr/share/keyrings/vscode.gpg

    echo "deb [signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main" \
      | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  fi
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

do_install_all() {
  apt_update
  install_core_packages
  setup_git_lfs
  install_or_update_starship
  install_or_update_docker
  install_or_update_hashicorp
  install_or_update_awscli
  install_or_update_vscode
}

do_update_only() {
  apt_update
  apt_upgrade
  install_or_update_starship
  install_or_update_docker
  install_or_update_hashicorp
  install_or_update_awscli
  install_or_update_vscode
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
 
