# Ubuntu Dev Box Build Scripts

Bootstrap scripts for setting up Ubuntu/Debian development VMs with a modern engineering toolchain.

## Quick Start (Fresh Ubuntu Install)

**All-in-One Script (Recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/setup-all.sh | sudo bash
```

**With Ubuntu Desktop GUI:**
```bash
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/setup-all.sh | sudo bash -s -- --gui
```

This will:
1. Install all development tools (Docker, Terraform, VS Code, etc.)
2. Create a `dev` user with passwordless sudo
3. Configure the system and apply all shell customizations
4. (Optional) Install Ubuntu Desktop with dev as default user

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

## Options

```bash
# Full setup with GUI desktop (creates dev user, default GDM user)
curl -fsSL ... | sudo bash -s -- --gui

# Headless server (no desktop, creates dev user)
curl -fsSL ... | sudo bash

# Skip dev user creation
curl -fsSL ... | sudo bash -s -- --no-dev-user

# Dev tools only (no system config)
curl -fsSL ... | sudo bash -s -- dev

# Full setup without desktop settings
curl -fsSL ... | sudo bash -s -- --no-desktop

# Prepare for imaging after setup
curl -fsSL ... | sudo bash -s -- clean
```

**Commands:**
| Command | Description |
|---------|-------------|
| `all` | Run dev + env setup (default) |
| `dev` | Install development tools only |
| `env` | Apply system/user configuration only |
| `clean` | Prepare system for imaging |
| `update` | Update all installed tools |

**Flags:**
| Flag | Description |
|------|-------------|
| `--gui` | Install Ubuntu Desktop / GNOME |
| `--no-desktop` | Skip desktop-specific settings |
| `--no-user-tweaks` | Skip per-user configurations |
| `--no-dev-user` | Don't create the dev user |
| `--no-shutdown` | Don't shutdown after clean |
| `--dry-run` | Show what would run |

---

## Alternative: Modular Scripts

If you prefer granular control, you can clone the repo and use the modular scripts:

```bash
git clone https://github.com/numbfrank/ubuntu-build.git
cd ubuntu-build

# Full setup (install tools + configure system + create dev user)
sudo ./setup.sh

# Or run individual components
sudo ./setup.sh dev      # Install dev tools only
sudo ./setup.sh env      # Configure system + create dev user
sudo ./setup.sh clean    # Prepare for imaging

# With options
sudo ./setup.sh --gui              # Include desktop installation
sudo ./setup.sh env --no-dev-user  # Configure without dev user
```

The modular approach uses:
- `setup.sh` — Controller script
- `setup-dev.sh` — Tool installation
- `setup-env.sh` — System configuration
- `setup-clean.sh` — Image cleanup

---

## What Gets Installed

### Development Tools

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

### System Configuration

### System Configuration

**System Settings:**
- NTP time sync
- Increased inotify limits (for IDEs/watchers)
- Higher nofile ulimits
- Disabled apport crash popups
- Capped journald disk usage
- UK locale, keyboard, and timezone

**Desktop Settings (with `--gui`):**
- Installs Ubuntu Desktop / GNOME
- Dock favorites: Terminal, VS Code, Chrome, Firefox, Settings
- Disables lid-close suspend
- Disables screen lock/timeout
- Disables browser first-run prompts
- Sets `dev` as default GDM login user

**Dev User (created by default):**
- Username: `dev`, Password: `dev`
- Passwordless sudo
- Member of `docker` group
- All aliases and integrations pre-configured

**User Tweaks (applied to both invoking user and dev):**
- SSH key generation (Ed25519 + RSA)
- SSH agent configuration
- Bash history improvements
- Shell aliases (Docker, Git, Terraform, system)
- Shell integrations (fzf, zoxide, delta)

### Image Cleanup (clean command)

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