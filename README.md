# Ubuntu development VM and server setup

`setup-all.sh` configures an Ubuntu or Debian development machine. It supports a GUI VM and a headless server with distinct package choices. It changes system packages and settings; take a backup or snapshot before applying it to an existing machine.

## Choose an install

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/numbfrank/ubuntu-build.git
cd ubuntu-build
```

| Machine | Command | Result |
| --- | --- | --- |
| VM with a desktop already installed | `sudo bash setup-all.sh` | Detects GNOME and adds desktop tools and browser policies. |
| Minimal VM that needs a desktop | `sudo bash setup-all.sh --desktop` | Installs GNOME and desktop tools supported on that architecture. |
| Headless VM or server | `sudo bash setup-all.sh --headless` | Installs CLI development tools without GUI packages or desktop settings. |

Run these commands from this repository's root directory. By default, the script creates and configures `dev` with the initial password `dev` on both desktop and headless machines. A full `all` run does not reboot automatically; reboot when convenient, or add `--reboot`.

Review the resolved choices without changing the machine:

```bash
bash setup-all.sh --headless --dry-run
```

### Default development account

A newly created `dev` account receives password `dev` and normal sudo access through the `sudo` group. The script does not add a passwordless sudo rule. An existing `dev` account keeps its current password; the script adds it to the sudo group and removes the exact passwordless sudo rule written by older versions of this script, if present.

Change the initial password immediately with `sudo passwd dev`. Add your SSH public key to `/home/dev/.ssh/authorized_keys` before remote login. Any SSH server that permits password login can expose the known `dev/dev` credential as soon as the account is created, including one already installed before this script runs. Keep network access restricted until you complete post-configuration. The `--ssh-server` option installs and enables OpenSSH without disabling password login.

To configure the account invoking `sudo` instead, use `--current-user`. To target another existing account, use `--user NAME`. Both choices skip creating `dev`.

## Profiles and options

| Option | Effect |
| --- | --- |
| No profile flag | Auto-detect an installed GNOME desktop; otherwise use the headless profile. |
| `--desktop` (`--gui`) | Select desktop routing. `all` or `env` installs GNOME; `all` or `dev` installs supported GUI tools. |
| `--headless` (`--console`, `--no-desktop`) | Skip desktop installation, GUI applications, fonts, and desktop settings. |
| `--current-user` (`--no-dev-user`) | Configure the account invoking `sudo` instead of creating `dev`. |
| `--user NAME` | Apply user settings to this account. `--user dev` creates `dev` if necessary. |
| `--dev-user` | Explicitly select the default `dev` account. |
| `--no-user-tweaks` | Skip per-user shell and SSH configuration. |
| `--uk-settings` | Set UK locale, keyboard, and timezone. |
| `--ssh-server` | Install and enable OpenSSH server for remote access. |
| `--reboot` | Reboot after a successful `all` run. |
| `--force` (`-f`) | Repeat a completed `all` setup. |
| `--dry-run` | Show the resolved command, profile, target user, and reboot choice. |

Desktop and headless flags conflict; choose one. Headless mode skips GUI installation and configuration but does not uninstall an existing desktop.

## Commands

Pass a command before or after the flags. `all` is the default. `dev --desktop` installs desktop tools without installing GNOME; use `all --desktop` or `env --desktop` when GNOME is needed.

| Command | Effect |
| --- | --- |
| `all` | Install tools and configure the system and selected user. |
| `dev` | Install development tools only. |
| `env` | Configure system and selected user only. |
| `update` | Update installed tools. |
| `clean` | Prepare a VM for capture as a reusable image. See below. |

Examples:

```bash
sudo bash setup-all.sh --headless --current-user
sudo bash setup-all.sh dev --headless
sudo bash setup-all.sh env --user alice
sudo bash setup-all.sh update --headless
sudo bash setup-all.sh --desktop --reboot
```

## Installed software and settings

| Component | Headless | Desktop |
| --- | --- | --- |
| Build tools, Git, Python, tmux, CLI utilities, fzf, zoxide, Starship, and GitHub CLI | Yes | Yes |
| git-delta | amd64 only | amd64 only |
| Docker CE, Compose, and Buildx | Yes | Yes |
| Terraform, Packer, and AWS CLI | Yes | Yes |
| VS Code | No | amd64, arm64, armhf |
| Google Chrome | No | amd64 only |
| GNOME desktop (installed with `--desktop`, detected otherwise) | No | Yes |
| Repository background for `dev` | No | Yes, on first GNOME login |

`all` and `dev` install the latest available Docker CE from Docker's official stable APT repository, with Compose and Buildx. `update` refreshes an installed Docker engine, and an identical `all` run refreshes Docker CE even when other setup is skipped. If distro `docker.io` is installed, the script checks all Docker CE package candidates before replacing it in one APT transaction. Migrating the engine can interrupt running containers; schedule the install accordingly.

The environment step configures time sync, file watcher and file descriptor limits, and journald size. Locale, keyboard, and timezone are preserved unless you pass `--uk-settings`. The desktop profile installs Hack Nerd Font and sets browser first-run defaults. It applies the repository background to `dev` on the first GNOME login, whether GNOME was already installed or added with `--desktop`; other users keep their wallpaper.

Per-user tweaks include Bash history, aliases, Git and shell integrations, and SSH client keepalive settings.

The script does not add users to the `docker` group, so a new installation normally needs `sudo` for Docker commands. If a trusted user needs Docker without `sudo`, follow the [Docker post-install steps](https://docs.docker.com/engine/install/linux-postinstall/); membership in the `docker` group grants root-level privileges.

## Reusable VM images

`clean` removes logs, caches, user history, SSH host keys, and machine identity, then shuts the VM down by default. Use it only on an image you intend to capture, not on a running server you want to keep using. It leaves the `dev` password, SSH private keys, credentials, tokens, and project files in place; remove or replace secrets separately before sharing the image.

```bash
sudo bash setup-all.sh clean
# To inspect the completed VM before powering it off:
sudo bash setup-all.sh clean --no-shutdown
```

See [Choosing a VM image](docs/VM-IMAGES.md) and the [Vagrant example](docs/Vagrantfile.example) for VM starting points.

## Requirements

- Ubuntu or Debian with `apt` and `systemd`
- Root access through `sudo` or a root shell
- Internet access to Ubuntu/Debian and third-party package repositories

The script configures third-party package repositories and runs downloaded installers for Starship, zoxide, and AWS CLI as root. Review the script and those sources before using it on an existing machine. `bash setup-all.sh --help` lists every command and flag.

## Testing

Run the no-root option and profile-routing checks from the repository root:

```bash
bash tests/test-options.sh
bash tests/test-dispatch.sh
bash tests/test-wallpaper.sh
bash tests/test-dev-user.sh
```

These checks verify CLI validation, profile choices, Docker migration planning, dev account setup, and the wallpaper first-login script without installing packages.

## License

MIT
