# Ubuntu Dev Box Build Scripts

Bootstrap scripts for setting up Ubuntu/Debian development VMs with a modern engineering toolchain.

## Quick Start (Fresh Ubuntu Install)

Run this one-liner on a fresh Ubuntu instance:

```bash
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash
```

This will:
1. Install git and clone the repository
2. Install all development tools (Docker, Terraform, VS Code, etc.)
3. Create a `dev` user with passwordless sudo
4. Configure the system and apply all shell customizations

---

## ⚠️ Important: Dev User

The bootstrap creates a dedicated **`dev` user** for all development activities:

| Setting | Value |
|---------|-------|
| **Username** | `dev` |
| **Password** | `dev` |
| **Sudo** | Passwordless (`NOPASSWD:ALL`) |
| **Groups** | `sudo`, `docker` |
| **Shell** | `/bin/bash` with Starship prompt |

### 🔐 Change the Password Immediately!

```bash
# After setup, change the dev user password:
sudo passwd dev

# Or login as dev and change it:
su - dev
passwd
```

### Using the Dev User

After setup, login as the `dev` user for development work:

```bash
# Switch to dev user
su - dev

# Or SSH directly (after adding your key)
ssh dev@<hostname>

# Or set as default login (desktop)
sudo usermod -s /bin/bash dev
```

The `dev` user has:
- All shell aliases pre-configured
- SSH keys generated (Ed25519 + RSA)
- SSH agent auto-start
- fzf, zoxide, and delta integrations
- Docker access without sudo

---

## Bootstrap Options

```bash
# Full setup (default) - creates dev user
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash

# Headless server (no desktop settings)
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- --no-desktop

# Dev tools only (no system config)
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- dev

# Skip dev user creation
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/bootstrap.sh | sudo bash -s -- --no-dev-user
```

---

## Manual Setup (If Already Cloned)

```bash
# Full setup (install tools + configure system + create dev user)
sudo ./setup.sh

# Or run individual components
sudo ./setup.sh dev      # Install dev tools only
sudo ./setup.sh env      # Configure system + create dev user
sudo ./setup.sh update   # Update existing tools
sudo ./setup.sh clean    # Prepare for imaging
```

---

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
| `--no-dev-user` | Don't create the dev user |
| `--no-shutdown` | Don't shutdown after clean |
| `--dry-run` | Show what would run without executing |

**Examples:**
```bash
sudo ./setup.sh                      # Full setup (creates dev user)
sudo ./setup.sh --no-dev-user        # Full setup without dev user
sudo ./setup.sh dev                  # Install tools only
sudo ./setup.sh env --no-desktop     # Configure headless server
sudo ./setup.sh update               # Update existing tools
sudo ./setup.sh clean --no-shutdown  # Prepare for imaging (no auto-shutdown)
```

---

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

### `setup-env.sh` - System Configuration

Applies system settings and creates the `dev` user:

**System Settings:**
- NTP time sync
- Increased inotify limits (for IDEs/watchers)
- Higher nofile ulimits
- Disabled apport crash popups
- Capped journald disk usage
- UK locale, keyboard, and timezone

**Dev User (created by default):**
- Username: `dev`, Password: `dev`
- Passwordless sudo
- Member of `docker` group
- All aliases and integrations pre-configured

**Desktop Settings:** *(disable with `--no-desktop`)*
- Disable lid-close suspend
- Disable screen lock/timeout
- Disable browser first-run prompts

**User Tweaks (applied to both invoking user and dev):**
- SSH key generation (Ed25519 + RSA)
- SSH agent configuration
- Bash history improvements
- Shell aliases (Docker, Git, Terraform, system)
- Shell integrations (fzf, zoxide, delta)

### `setup-clean.sh` - Image Cleanup

Prepares the system for imaging (golden image/VM template):

- APT cache cleanup
- Log truncation and journald vacuum
- Temp directory cleanup
- User history and cache removal
- SSH host key removal (regenerated on first boot)
- Machine-id reset

---

## Shell Aliases

After setup, these aliases are available for the `dev` user:

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

---

## Vagrant Quick Start

See [docs/Vagrantfile.example](docs/Vagrantfile.example) for a ready-to-use Vagrantfile:

```bash
# Copy the example
cp docs/Vagrantfile.example Vagrantfile

# Start VM (provisions automatically)
vagrant up

# Connect as vagrant user
vagrant ssh

# Switch to dev user
su - dev  # password: dev
```

---

## Requirements

- Ubuntu 20.04+ or Debian 11+
- sudo access
- Internet connection

---

## Security Checklist

After running the bootstrap:

- [ ] Change the `dev` user password: `sudo passwd dev`
- [ ] Add your SSH public key to `/home/dev/.ssh/authorized_keys`
- [ ] Consider disabling password auth: `PasswordAuthentication no` in `/etc/ssh/sshd_config`
- [ ] Review `/etc/sudoers.d/90-dev-nopasswd` if you want to restrict sudo

---

## License

MIT