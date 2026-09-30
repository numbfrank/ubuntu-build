#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -s "$repo_dir/files/dev-background.png" ]] || { printf 'Dev background asset is missing\n' >&2; exit 1; }
# The installer guards main, so sourcing it only defines functions and defaults.
# shellcheck disable=SC1091
source "$repo_dir/setup-all.sh"

calls=""
record() { calls+=" $1"; }
assert_called() {
  if [[ " $calls " != *" $1 "* ]]; then
    printf 'Expected %s in call list: %s\n' "$1" "$calls" >&2
    exit 1
  fi
}
assert_not_called() {
  if [[ " $calls " == *" $1 "* ]]; then
    printf 'Unexpected %s in call list: %s\n' "$1" "$calls" >&2
    exit 1
  fi
}

# Stub every side effect and verify which paths the real command runner selects.
apt_update() { :; }
apt_upgrade() { :; }
install_core_packages() { record core; }
setup_git_lfs() { :; }
install_or_update_delta() { :; }
install_or_update_zoxide() { :; }
install_or_update_starship() { :; }
install_or_update_docker() { :; }
install_or_update_hashicorp() { :; }
install_or_update_awscli() { :; }
install_or_update_github_cli() { :; }
install_or_update_vscode() { record vscode; }
install_or_update_chrome() { record chrome; }
test_arch=amd64
dpkg() {
  if [[ "$1" == "--print-architecture" ]]; then
    printf '%s\n' "$test_arch"
  else
    command dpkg "$@"
  fi
}

UPDATE_ONLY=0
DO_UPDATE=0
RESOLVED_PROFILE=headless
do_dev >/dev/null
assert_called core
assert_not_called vscode
assert_not_called chrome

calls=""
RESOLVED_PROFILE=desktop
do_dev >/dev/null
assert_called vscode
assert_called chrome

calls=""
test_arch=arm64
do_dev >/dev/null
assert_called vscode
assert_not_called chrome
test_arch=amd64

enable_ntp() { :; }
set_inotify_limits() { :; }
set_ulimits() { :; }
disable_apport() { :; }
cap_journald() { :; }
ensure_ssh_client() { :; }
ensure_pkg() { :; }
set_uk_locale() { record uk; }
install_ubuntu_desktop() { record gnome; }
create_dev_user() { record dev_user; }
install_dev_background() { record background; }
install_nerd_fonts() { record font; }
disable_browser_first_run() { record browser; }
apply_user_tweaks() { record user_tweaks; }

APPLY_UK_SETTINGS=0
CREATE_DEV_USER=1
DO_USER_TWEAKS=0
TARGET_USER=test
calls=""
INSTALL_GUI=0
RESOLVED_PROFILE=headless
do_env >/dev/null
assert_not_called gnome
assert_not_called font
assert_not_called browser
assert_not_called background

calls=""
INSTALL_GUI=0
RESOLVED_PROFILE=desktop
do_env >/dev/null
assert_not_called gnome
assert_called font
assert_called browser
assert_called background

calls=""
CREATE_DEV_USER=0
do_env >/dev/null
assert_not_called background

calls=""
CREATE_DEV_USER=1
INSTALL_GUI=1
RESOLVED_PROFILE=desktop
do_env >/dev/null
assert_called gnome
assert_called font
assert_called browser
assert_called background

printf 'Installer dispatch checks passed.\n'

# A completed run should skip the same plan, but apply newly requested options.
marker_dir="$(mktemp -d)"
trap 'rm -rf "$marker_dir"' EXIT
SETUP_MARKER="$marker_dir/completed"
run_count=0
docker_refreshes=0
do_dev() { ((run_count+=1)); }
do_env() { :; }
install_or_update_docker() { ((docker_refreshes+=1)); }
TARGET_USER=test
RESOLVED_PROFILE=headless
INSTALL_PROFILE=headless
INSTALL_GUI=0
CREATE_DEV_USER=1
DO_USER_TWEAKS=0
APPLY_UK_SETTINGS=0
INSTALL_SSH_SERVER=0
REBOOT_AFTER=0
FORCE_RERUN=0

do_all >/dev/null
[[ "$run_count" -eq 1 ]] || { printf 'First full setup did not run\n' >&2; exit 1; }
do_all >/dev/null
[[ "$run_count" -eq 1 && "$docker_refreshes" -eq 1 ]] || {
  printf 'Identical plan did not refresh Docker CE alone\n' >&2; exit 1;
}
INSTALL_SSH_SERVER=1
do_all >/dev/null
[[ "$run_count" -eq 2 ]] || { printf 'Changed SSH option was skipped by marker\n' >&2; exit 1; }
sed -i '/^setup_schema=/d' "$SETUP_MARKER"
do_all >/dev/null
[[ "$run_count" -eq 3 ]] || { printf 'Legacy marker did not trigger the new setup schema\n' >&2; exit 1; }

printf 'Installer marker checks passed.\n'

# Docker CE migration checks every package candidate before removing distro packages.
(
  source "$repo_dir/setup-all.sh"
  docker_log="$(mktemp)"
  trap 'rm -f "$docker_log"' EXIT
  pkg_installed() { [[ "$1" == docker.io || "$1" == containerd ]]; }
  ensure_docker_repo() { printf 'repo\n' >> "$docker_log"; }
  apt_update() { printf 'update\n' >> "$docker_log"; }
  apt-cache() {
    printf 'policy %s\n' "$2" >> "$docker_log"
    printf 'Candidate: 5:29.0.0-1\n'
  }
  apt-get() { printf 'apt %s\n' "$*" >> "$docker_log"; }
  systemctl() { :; }
  groupadd() { :; }
  UPDATE_ONLY=0
  install_or_update_docker >/dev/null
  [[ "$(grep -c '^policy ' "$docker_log")" -eq 5 ]] || {
    printf 'Docker CE package candidate preflight was incomplete\n' >&2; exit 1;
  }
  grep -q '^apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io- containerd-$' "$docker_log" || {
    printf 'Docker CE and conflicts were not in one APT install request\n' >&2; exit 1;
  }
  [[ "$(grep -c '^apt ' "$docker_log")" -eq 1 ]] || {
    printf 'Docker migration used more than one APT transaction\n' >&2; exit 1;
  }
  last_policy="$(grep -n '^policy ' "$docker_log" | tail -1 | cut -d: -f1)"
  first_install="$(grep -n '^apt install ' "$docker_log" | head -1 | cut -d: -f1)"
  [[ "$last_policy" -lt "$first_install" ]] || {
    printf 'Docker APT transaction preceded package preflight\n' >&2; exit 1;
  }

  : > "$docker_log"
  UPDATE_ONLY=1
  install_or_update_docker >/dev/null
  grep -q '^apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io- containerd-$' "$docker_log" || {
    printf 'Update did not migrate distro Docker to CE\n' >&2; exit 1;
  }
)

# A missing Docker CE candidate must leave the distro engine installed.
(
  source "$repo_dir/setup-all.sh"
  docker_log="$(mktemp)"
  trap 'rm -f "$docker_log"' EXIT
  pkg_installed() { [[ "$1" == docker.io ]]; }
  ensure_docker_repo() { :; }
  apt_update() { :; }
  apt-cache() {
    if [[ "$2" == containerd.io ]]; then
      printf 'Candidate: (none)\n'
    else
      printf 'Candidate: 5:29.0.0-1\n'
    fi
  }
  apt-get() { printf 'apt %s\n' "$*" >> "$docker_log"; }
  if install_or_update_docker >/dev/null 2>&1; then
    printf 'Missing Docker CE candidate was accepted\n' >&2
    exit 1
  fi
  [[ ! -s "$docker_log" ]] || {
    printf 'Existing Docker was changed without a complete CE candidate set\n' >&2; exit 1;
  }
)
printf 'Installer Docker migration checks passed.\n'

# dpkg retains records for removed packages; held packages can still be installed.
(
  source "$repo_dir/setup-all.sh"
  query_status="ii "
  dpkg-query() { printf '%s' "$query_status"; }
  pkg_installed example || { printf 'Installed package was not detected\n' >&2; exit 1; }
  query_status="hi "
  pkg_installed example || { printf 'Held installed package was not detected\n' >&2; exit 1; }
  query_status="rc "
  if pkg_installed example; then
    printf 'Removed package was detected as installed\n' >&2
    exit 1
  fi
)
printf 'Installer package-state checks passed.\n'
