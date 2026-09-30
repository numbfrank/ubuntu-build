#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/setup-all.sh"

assert_contains() {
  local output="$1" pattern="$2"
  if ! grep -Eiq -- "$pattern" <<<"$output"; then
    printf 'Expected output to match %s:\n%s\n' "$pattern" "$output" >&2
    exit 1
  fi
}

assert_lacks() {
  local output="$1" pattern="$2"
  if grep -Eiq -- "$pattern" <<<"$output"; then
    printf 'Unexpected output matching %s:\n%s\n' "$pattern" "$output" >&2
    exit 1
  fi
}

assert_fails() {
  local output
  if output="$(bash "$installer" "$@" 2>&1)"; then
    printf 'Expected command to fail: %s\n%s\n' "$*" "$output" >&2
    exit 1
  fi
}

bash -n "$installer"

help="$(bash "$installer" --help)"
assert_contains "$help" '--headless'
assert_contains "$help" '--desktop'
assert_contains "$help" '--dev-user'
assert_contains "$help" '--reboot'

# The default plan creates and targets dev on either install profile.
default_headless="$(bash "$installer" --dry-run --headless)"
assert_contains "$default_headless" 'Target user: dev'
assert_contains "$default_headless" 'Create dev user: yes'
default_desktop="$(bash "$installer" --dry-run --desktop)"
assert_contains "$default_desktop" 'Target user: dev'
assert_contains "$default_desktop" 'Create dev user: yes'
assert_contains "$default_desktop" 'Dev background: apply at next GNOME login'
other_user_desktop="$(bash "$installer" --dry-run --desktop --user root)"
assert_lacks "$other_user_desktop" 'Dev background:'

headless="$(bash "$installer" --dry-run --headless --dev-user)"
assert_contains "$headless" 'headless'
alias_headless="$(bash "$installer" --dry-run --no-desktop --dev-user)"
assert_contains "$alias_headless" 'Profile: headless'
assert_contains "$headless" 'GUI packages: no|GUI packages.*skip|skip.*GUI packages'
assert_contains "$headless" 'reboot: no|reboot.*disabled|no reboot'

desktop="$(bash "$installer" --dry-run --desktop --dev-user --reboot)"
assert_contains "$desktop" 'desktop'
assert_contains "$desktop" 'GUI packages: yes|GUI packages.*install|install.*GUI packages'
assert_contains "$desktop" 'reboot: yes|reboot.*enabled|will reboot'

dev_plan="$(bash "$installer" dev --dry-run --desktop)"
assert_contains "$dev_plan" 'Desktop installation: no'
assert_contains "$dev_plan" 'Target user: not used'

env_plan="$(bash "$installer" env --dry-run --desktop --dev-user)"
assert_contains "$env_plan" 'GUI packages: no'
assert_contains "$env_plan" 'Desktop installation: yes'

clean_plan="$(bash "$installer" clean --dry-run --no-shutdown)"
assert_contains "$clean_plan" 'Shutdown: no'

assert_fails --dry-run --desktop --headless --dev-user
assert_fails --dry-run --gui --console --dev-user
assert_fails --dry-run --user
assert_fails --dry-run --user --desktop
assert_fails --dry-run --unknown-option
assert_fails clean --dry-run --reboot
assert_fails all --dry-run --no-shutdown --dev-user
assert_fails dev --dry-run --dev-user
assert_fails all --dry-run --replace-docker

printf 'Installer option checks passed.\n'
