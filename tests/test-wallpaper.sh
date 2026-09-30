#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/setup-all.sh"
[[ -s "$repo_dir/files/dev-background.png" ]] || {
  printf 'Dev background asset is missing\n' >&2
  exit 1
}

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/home/.config/autostart"
touch "$test_dir/home/.config/autostart/dev-background.desktop"

# Extract the first-login script that the installer writes for dev.
awk '
  index($0, "cat > /usr/local/lib/ubuntu-build/set-dev-background <<") { copy=1; next }
  copy && $0 == "EOF" { exit }
  copy { print }
' "$installer" > "$test_dir/set-dev-background"
[[ -s "$test_dir/set-dev-background" ]] || {
  printf 'Dev first-login wallpaper script was not found\n' >&2
  exit 1
}
bash -n "$test_dir/set-dev-background"

cat > "$test_dir/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WALLPAPER_LOG"
EOF
chmod +x "$test_dir/bin/gsettings"

HOME="$test_dir/home" WALLPAPER_LOG="$test_dir/gsettings.log" \
  PATH="$test_dir/bin:$PATH" bash "$test_dir/set-dev-background"

uri='file:///usr/share/backgrounds/dev-background.png'
grep -Fxq "set org.gnome.desktop.background picture-uri $uri" "$test_dir/gsettings.log"
grep -Fxq "set org.gnome.desktop.background picture-uri-dark $uri" "$test_dir/gsettings.log"
grep -Fxq 'set org.gnome.desktop.background picture-options zoom' "$test_dir/gsettings.log"
[[ ! -e "$test_dir/home/.config/autostart/dev-background.desktop" ]] || {
  printf 'One-time wallpaper autostart entry was not removed\n' >&2
  exit 1
}

printf 'Dev wallpaper first-login checks passed.\n'
