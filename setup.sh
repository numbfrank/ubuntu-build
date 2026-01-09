#!/usr/bin/env bash
set -euo pipefail

# Ubuntu Dev Box Setup Controller
# Orchestrates setup-dev.sh, setup-env.sh, and setup-clean.sh
#
# Usage:
#   ./setup.sh [command] [options]
#
# Commands:
#   all          Run dev + env setup (default)
#   dev          Install development tools only
#   env          Apply system/user configuration only
#   clean        Prepare system for imaging
#   update       Update all installed tools
#
# Options:
#   --no-desktop       Skip desktop-specific settings (env)
#   --no-user-tweaks   Skip per-user configurations (env)
#   --user <name>      Specify target user (env)
#   --no-shutdown      Don't shutdown after clean
#   --dry-run          Show what would be run without executing
#   -h, --help         Show this help message
#
# Examples:
#   ./setup.sh                    # Full setup (dev + env)
#   ./setup.sh dev                # Install tools only
#   ./setup.sh env --no-desktop   # Configure headless server
#   ./setup.sh update             # Update existing tools
#   ./setup.sh clean --no-shutdown

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="all"
DRY_RUN=0
PASS_THROUGH_ARGS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()     { printf "${BLUE}[%s]${NC} %s\n" "$(date +'%F %T')" "$*"; }
success() { printf "${GREEN}[%s] ✓${NC} %s\n" "$(date +'%F %T')" "$*"; }
warn()    { printf "${YELLOW}[%s] ⚠${NC} %s\n" "$(date +'%F %T')" "$*"; }
error()   { printf "${RED}[%s] ✗${NC} %s\n" "$(date +'%F %T')" "$*" >&2; }

usage() {
  sed -n '3,32p' "$0" | sed 's/^# \?//'
  exit 0
}

check_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run with sudo"
    echo "  sudo $0 $*"
    exit 1
  fi
}

check_script_exists() {
  local script="$1"
  if [[ ! -x "$script" ]]; then
    error "Script not found or not executable: $script"
    exit 1
  fi
}

run_script() {
  local script="$1"
  shift
  local args=("$@")
  
  check_script_exists "$script"
  
  log "Running: $(basename "$script") ${args[*]:-}"
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY RUN: Would execute: $script ${args[*]:-}"
    return 0
  fi
  
  if "$script" "${args[@]:-}"; then
    success "Completed: $(basename "$script")"
  else
    error "Failed: $(basename "$script")"
    exit 1
  fi
}

do_dev() {
  run_script "${SCRIPT_DIR}/setup-dev.sh" "${PASS_THROUGH_ARGS[@]:-}"
}

do_env() {
  run_script "${SCRIPT_DIR}/setup-env.sh" "${PASS_THROUGH_ARGS[@]:-}"
}

do_clean() {
  run_script "${SCRIPT_DIR}/setup-clean.sh" "${PASS_THROUGH_ARGS[@]:-}"
}

do_update() {
  PASS_THROUGH_ARGS+=("--update-only")
  run_script "${SCRIPT_DIR}/setup-dev.sh" "${PASS_THROUGH_ARGS[@]:-}"
}

do_all() {
  log "Starting full setup (dev + env)"
  echo ""
  do_dev
  echo ""
  do_env
  echo ""
  success "Full setup complete!"
  log "Note: Re-login required for Docker group membership and shell changes"
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
      # Pass through to sub-scripts
      --no-desktop|--no-user-tweaks|--no-shutdown|--update|--update-only|--no-dev-user)
        PASS_THROUGH_ARGS+=("$1")
        shift
        ;;
      --user)
        PASS_THROUGH_ARGS+=("$1" "$2")
        shift 2
        ;;
      --keep-*)
        PASS_THROUGH_ARGS+=("$1")
        shift
        ;;
      --cloud-init-clean)
        PASS_THROUGH_ARGS+=("$1")
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

main() {
  parse_args "$@"
  
  # Check sudo for all commands except help/dry-run
  if [[ "$DRY_RUN" -eq 0 ]]; then
    check_sudo "$@"
  fi
  
  log "Ubuntu Dev Box Setup"
  log "Command: $COMMAND"
  [[ ${#PASS_THROUGH_ARGS[@]} -gt 0 ]] && log "Options: ${PASS_THROUGH_ARGS[*]}"
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