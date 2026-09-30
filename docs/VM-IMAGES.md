# Choosing a VM image

Choose an image that matches how you will use the machine. The setup script supports Ubuntu and Debian; it can install a desktop when requested, but a desktop installer image is usually the simplest starting point for a GUI VM.

| Use | Starting image | Setup profile |
| --- | --- | --- |
| GUI VM with GNOME installed | [Ubuntu Desktop ISO](https://ubuntu.com/download/desktop) or a [Debian live GNOME image](https://www.debian.org/distrib/) | Default auto profile |
| Minimal VM that needs GNOME | Ubuntu Server ISO or a Debian base install | `--desktop` |
| Headless VM or server | [Ubuntu Server ISO](https://ubuntu.com/download/server), [Ubuntu release cloud image](https://cloud-images.ubuntu.com/releases/), or a [Debian cloud image](https://www.debian.org/distrib/) | `--headless` |

The `--desktop` profile also works on a minimal VM if you want the script to install the desktop packages. Allow enough disk space and memory for a full graphical environment. The `--headless` profile omits GUI applications and desktop settings.

## Cloud images

Cloud images use cloud-init for first-boot setup. Add your SSH public key and configure the initial account through your VM platform or a cloud-init seed **before booting**. Do not expect a usable default password. The usual Ubuntu account is `ubuntu`; Debian's default account varies by platform (the generic cloud image uses `debian`). See the [Ubuntu cloud-image documentation](https://documentation.ubuntu.com/public-images/) and [Debian cloud-image FAQ](https://wiki.debian.org/Cloud) for details.

For a local hypervisor, use the image format and guest settings recommended by its documentation. [Ubuntu release cloud images](https://cloud-images.ubuntu.com/releases/) and [Debian cloud images](https://cloud.debian.org/images/cloud/) provide downloadable disk images; desktop and server ISOs provide an interactive installer instead.

## Vagrant

Use `vagrant ssh` to enter a Vagrant VM, then `su - dev` with the initial `dev` password after provisioning. The chosen box and provider determine the Vagrant login account and authentication. The repository's [Vagrant example](Vagrantfile.example) shows a starting configuration; review its box, provider, resources, and provisioning profile before `vagrant up`.

## After installation

By default the setup script creates `dev` with the initial password `dev`. Change that password with `sudo passwd dev` after setup and add your SSH public key before logging into `dev` remotely. If an existing SSH server allows password login, the known `dev/dev` credential can be used while it remains unchanged; keep network access restricted until post-configuration is complete. An existing `dev` account keeps its current password.

Run the script's `clean` command only on a VM you are preparing to capture as a reusable image: it removes SSH host keys, machine ID, logs, history, and caches, then shuts down by default. It does not reset the `dev` password or remove SSH private keys, tokens, credentials, or project files; audit those before sharing an image.
