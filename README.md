# Ubuntu Dev Box Build Scripts

Bootstrap scripts for setting up Ubuntu/Debian development VMs with a modern engineering toolchain.

## Quick Start (Fresh Ubuntu Install)

Run this one-liner on a fresh Ubuntu instance:

```bash
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash
```

**With options:**
```bash
# Headless server (no desktop settings)
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- --no-desktop

# Dev tools only
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- dev
```

## Manual Setup (If Already Cloned)

```bash
# Full setup (install tools + configure system)
sudo ./setup.sh

# Or run individual components
sudo ./setup.sh dev      # Install dev tools only
sudo ./setup.sh env      # Configure system only
sudo ./setup.sh update   # Update existing tools
sudo ./setup.sh clean    # Prepare for imaging
```

## Controller Script: `setup.sh`

The main entry point that orchestrates all setup scripts.

**Commands:**
| Command | Description |
|---------|-------------|
| `all` | Run dev + env setup (default) |
| `dev` | Install development tools only |
| `env` | Apply system/user configuration only |
| `clean` | Prepare system for imaging |
| `update` | Update all installed tools |

**Options:**
| Option | Description |
|--------|-------------|
| `--no-desktop` | Skip desktop-specific settings |
| `--no-user-tweaks` | Skip per-user configurations |
| `--user <name>` | Specify target user |
| `--no-shutdown` | Don't shutdown after clean |
| `--dry-run` | Show what would run without executing |

**Examples:**
```bash
sudo ./setup.sh                      # Full setup (dev + env)
sudo ./setup.sh dev                  # Install tools only
sudo ./setup.sh env --no-desktop     # Configure headless server
sudo ./setup.sh update               # Update existing tools
sudo ./setup.sh clean --no-shutdown  # Prepare for imaging (no auto-shutdown)
sudo ./setup.sh --dry-run            # Preview what would run
```

## Scripts

### `setup-dev.sh` - Development Tools Installation

Installs a complete development environment:

| Category | Tools |
|----------|-------|
| **Core** | git, git-lfs, build-essential, python3, tmux, vim |
| **CLI** | jq, ripgrep, fd, bat, fzf, htop, tree |
| **Prompt** | Starship |
| **Containers** | Docker Engine, Docker Compose, Buildx |
| **IaC** | Terraform, Packer |
| **Cloud** | AWS CLI v2 |
| **Editors** | VS Code |
| **Git Tools** | GitHub CLI (gh), git-delta |
| **Navigation** | zoxide |
| **Browser** | Google Chrome |

**Flags:**
- `--update` - Install + update existing tools
- `--update-only` - Only update what's already installed

### `setup-env.sh` - System Configuration

Applies one-off system and user configurations:

**System Settings:**
- NTP time sync
- Increased inotify limits (for IDEs/watchers)
- Higher nofile ulimits
- Disabled apport crash popups
- Capped journald disk usage
- UK locale, keyboard, and timezone

**Desktop Settings:** *(disable with `--no-desktop`)*
- Disable lid-close suspend
- Disable screen lock/timeout
- Disable browser first-run prompts (Firefox, Chrome, Edge)

**User Tweaks:** *(disable with `--no-user-tweaks`)*
- SSH key generation (Ed25519 + RSA)
- SSH agent configuration
- Bash history improvements
- SSH keepalive defaults
- Shell aliases (Docker, Git, Terraform, system)
- Shell integrations (fzf, zoxide, delta)
- Docker tool aliases (lazydocker, lazygit)

**Flags:**
- `--no-desktop` - Skip desktop-specific settings
- `--no-user-tweaks` - Skip per-user configurations
- `--user <name>` - Specify target user (default: invoking user)

### `setup-clean.sh` - Image Cleanup

Prepares the system for imaging (golden image/VM template):

- APT cache cleanup
- Log truncation and journald vacuum
- Temp directory cleanup
- User history and cache removal
- SSH host key removal (regenerated on first boot)
- Machine-id reset
- Optional cloud-init cleanup

**Flags:**
- `--keep-ssh-host-keys` - Preserve SSH host keys
- `--keep-machine-id` - Preserve machine-id
- `--keep-logs` - Preserve logs
- `--keep-user-history` - Preserve shell histories
- `--keep-caches` - Preserve user caches
- `--cloud-init-clean` - Run cloud-init cleanup
- `--no-shutdown` - Don't shutdown after cleanup

### `setup.sh` - Ansible Bootstrap

Installs Ansible for running the included playbooks (legacy approach).

## Shell Aliases

After running `setup-env.sh`, these aliases are available:

**Docker:**
```bash
dps, dpsa, di, dlogs, dexec, docker-clean, docker-stop-all
lazydocker, lazygit  # Run as containers
```

**Git:**
```bash
gs, gp, gc, gco, gb, gl, gd, gundo, gamend, gstash, gpop
gupdate  # Fetch and rebase from origin/main
gclean   # Cleanup merged branches + gc
```

**Terraform:**
```bash
tf, tfi, tfp, tfa, tfd
```

**System:**
```bash
ll, la, ports, listening, meminfo, diskinfo, cpuinfo, myip
mkcd, extract, backup  # Utility functions
```

## Requirements

- Ubuntu 20.04+ or Debian 11+
- sudo access
- Internet connection

## License

MIT