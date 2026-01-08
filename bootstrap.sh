#!/usr/bin/env bash
set -euo pipefail

# Ubuntu Dev Box Bootstrap Script
# Downloads and runs the setup scripts on a fresh Ubuntu instance
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- [command] [options]
#
# Commands (passed to setup.sh):
#   all                Full setup: dev + env (default)
#   dev                Install development tools only
#   env                Apply system/user configuration only
#   update             Update existing tools only
#   clean              Prepare system for imaging
#
# Options (passed to setup.sh):
#   --no-desktop       Skip desktop-specific settings
#   --no-user-tweaks   Skip per-user configurations
#   --user <name>      Specify target user
#   --no-shutdown      Don't shutdown after clean
#
# Examples:
#   curl ... | sudo bash                        # Full setup (dev + env)
#   curl ... | sudo bash -s -- dev              # Dev tools only
#   curl ... | sudo bash -s -- env --no-desktop # Headless server config
#   curl ... | sudo bash -s -- update           # Update existing tools

REPO_URL="${UBUNTU_BUILD_REPO:-https://github.com/numbfrank/ubuntu-build.git}"
INSTALL_DIR="${UBUNTU_BUILD_DIR:-/opt/ubuntu-build}"
BRANCH="${UBUNTU_BUILD_BRANCH:-main}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { printf "${BLUE}[bootstrap]${NC} %s\n" "$*"; }
success() { printf "${GREEN}[bootstrap] ✓${NC} %s\n" "$*"; }
error()   { printf "${RED}[bootstrap] ✗${NC} %s\n" "$*" >&2; exit 1; }

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
  fi
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS - /etc/os-release not found"
  fi
  
  # shellcheck disable=SC1091
  . /etc/os-release
  
  case "${ID:-}" in
    ubuntu|debian)
      log "Detected: ${PRETTY_NAME:-$ID}"
      ;;
    *)
      error "Unsupported OS: ${ID:-unknown}. This script supports Ubuntu/Debian only."
      ;;
  esac
}

install_git() {
  if command -v git >/dev/null 2>&1; then
    log "Git already installed"
    return 0
  fi
  
  log "Installing git..."
  apt-get update -y
  apt-get install -y git
  success "Git installed"
}

clone_repo() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Repository already exists, pulling latest..."
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard "origin/${BRANCH}"
  else
    log "Cloning repository..."
    rm -rf "$INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  success "Repository ready at $INSTALL_DIR"
}

run_setup() {
  cd "$INSTALL_DIR"
  chmod +x setup.sh setup-dev.sh setup-env.sh setup-clean.sh
  
  log "Running setup.sh $*"
  ./setup.sh "$@"
}

cleanup() {
  # Optionally remove install dir after setup
  # rm -rf "$INSTALL_DIR"
  :
}

main() {
  echo ""
  log "Ubuntu Dev Box Bootstrap"
  log "========================"
  echo ""
  
  check_root
  check_os
  install_git
  clone_repo
  run_setup "$@"
  cleanup
  
  echo ""
  success "Bootstrap complete!"
  log "Re-login required for all changes to take effect"
  echo ""
}

main "$@"
