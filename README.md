# Ubuntu Dev Box Build Scripts

A single script to set up Ubuntu/Debian development VMs (and WSL) with a modern engineering toolchain.

## Quick Start

**From the repo (run in repo root):**
```bash
sudo bash setup-all.sh
```

**One-liner (curl):**
```bash
curl -fsSL https://raw.githubusercontent.com/numbfrank/ubuntu-build/main/setup-all.sh | sudo bash
```

**Console/WSL only (no GUI):**
```bash
sudo bash setup-all.sh --console
```

**With Ubuntu Desktop GUI:**
```bash
sudo bash setup-all.sh --gui
# or: curl -fsSL ... | sudo bash -s -- --gui
```

**Current user only (no dev user):**
```bash
sudo bash setup-all.sh --console --current-user
```

Default run will:
1. Install all development tools (Docker, Terraform, VS Code, etc.)
2. Create a `dev` user with passwordless sudo (unless you use `--current-user` or `--user <name>`)
3. Configure the system and apply shell customizations to the target user(s)
4. (Optional with `--gui`) Install Ubuntu Desktop with dev as default user

---

## ⚠️ Important: Dev User (optional)

By default the bootstrap creates a dedicated **`dev` user**. Use `--current-user` or `--user <name>` to set up only a specific user and skip creating `dev`.

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
# Full setup (creates dev user, applies to both current user and dev)
sudo bash setup-all.sh

# Console/WSL only
sudo bash setup-all.sh --console

# Current user only (no dev user)
sudo bash setup-all.sh --console --current-user

# Create dev user and apply config to dev only
sudo bash setup-all.sh --dev-user

# Apply config to a specific user only (no dev unless name is 'dev')
sudo bash setup-all.sh env --user user
sudo bash setup-all.sh --user user --force   # full re-run for user "user"

# Full setup with GUI desktop
sudo bash setup-all.sh --gui

# Dev tools only (no system config)
sudo bash setup-all.sh dev

# Env/config only
sudo bash setup-all.sh env

# Prepare for imaging after setup
sudo bash setup-all.sh clean
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
| `--console` | Console/WSL only: no GUI, skip desktop settings |
| `--gui` | Install Ubuntu Desktop / GNOME |
| `--no-desktop` | Skip desktop-specific settings |
| `--current-user` | Apply config to current user only (do not create dev user) |
| `--dev-user` | Create dev user and apply config to dev only |
| `--user NAME` | Apply config to NAME only (create dev only if NAME is `dev`) |
| `--no-dev-user` | Don't create the dev user |
| `--no-user-tweaks` | Skip per-user configurations |
| `--force`, `-f` | Force re-run even if setup already completed |
| `--no-shutdown` | Don't shutdown after clean |
| `--dry-run` | Show what would run |

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

**Dev User (created by default unless `--current-user` or `--user <other>`):**
- Username: `dev`, Password: `dev`
- Passwordless sudo
- Member of `docker` group
- All aliases and integrations pre-configured

**User Tweaks (applied to target user(s)—see `--current-user`, `--dev-user`, `--user`):**
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
mkcd, take, extract, backup  # Utility functions
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