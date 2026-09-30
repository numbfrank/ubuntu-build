#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The installer guards main when sourced.
# shellcheck disable=SC1091
source "$repo_dir/setup-all.sh"

test_dir="$(mktemp -d)"
trap '/bin/rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/home"
calls="$test_dir/calls"
legacy_sudoers="$test_dir/legacy_sudoers"

# Redirect the function's fixed legacy sudoers path into this test directory.
declare -f create_dev_user |
  sed "s#/etc/sudoers.d/90-dev-nopasswd#$legacy_sudoers#g" > "$test_dir/create_dev_user.sh"
if grep -Fq '/etc/sudoers.d/90-dev-nopasswd' "$test_dir/create_dev_user.sh"; then
  printf 'Legacy sudoers path was not isolated\n' >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$test_dir/create_dev_user.sh"

account_exists=0
id() { [[ "$account_exists" -eq 1 ]]; }
useradd() { printf 'useradd %s\n' "$*" >> "$calls"; }
usermod() { printf 'usermod %s\n' "$*" >> "$calls"; }
chpasswd() {
  local credential
  IFS= read -r credential
  printf 'chpasswd %s\n' "$credential" >> "$calls"
}
getent() {
  [[ "$1" == passwd && "$2" == dev ]] || return 1
  printf 'dev:x:1234:1234::%s/home:/bin/bash\n' "$test_dir"
}
rm() {
  [[ "$1" == -f && "$2" == "$legacy_sudoers" ]] || {
    printf 'Unexpected removal attempted: %s\n' "$*" >&2
    return 1
  }
  printf 'legacy sudoers removal requested\n' >> "$calls"
}

printf 'dev ALL=(ALL) NOPASSWD:ALL\n' > "$legacy_sudoers"
create_dev_user >/dev/null
grep -Fxq 'useradd -m -s /bin/bash -G sudo dev' "$calls"
grep -Fxq 'chpasswd dev:dev' "$calls"
grep -Fxq 'legacy sudoers removal requested' "$calls"
[[ "$TARGET_HOME" == "$test_dir/home" ]]

: > "$calls"
account_exists=1
create_dev_user >/dev/null
grep -Fxq 'usermod -aG sudo dev' "$calls"
if grep -Eq '^(useradd|chpasswd) ' "$calls"; then
  printf 'Existing dev account credentials were changed\n' >&2
  exit 1
fi

printf 'Installer dev-account checks passed.\n'
