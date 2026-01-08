# VM Images & Default Credentials

Quick reference for obtaining VM images and their default login credentials.

## Ubuntu Cloud Images

**Official Downloads:** https://cloud-images.ubuntu.com/

| Version | Codename | Download |
|---------|----------|----------|
| 24.04 LTS | Noble | [noble/current](https://cloud-images.ubuntu.com/noble/current/) |
| 22.04 LTS | Jammy | [jammy/current](https://cloud-images.ubuntu.com/jammy/current/) |
| 20.04 LTS | Focal | [focal/current](https://cloud-images.ubuntu.com/focal/current/) |

**Default Credentials:**
- Username: `ubuntu`
- Password: *none* (SSH key auth via cloud-init)
- Root: disabled

> Cloud images require cloud-init for initial configuration. Use a seed ISO or metadata service to inject SSH keys.

---

## Debian Cloud Images

**Official Downloads:** https://cloud.debian.org/images/cloud/

| Version | Codename | Download |
|---------|----------|----------|
| 12 | Bookworm | [bookworm/latest](https://cloud.debian.org/images/cloud/bookworm/latest/) |
| 11 | Bullseye | [bullseye/latest](https://cloud.debian.org/images/cloud/bullseye/latest/) |

**Default Credentials:**
- Username: `debian`
- Password: *none* (SSH key auth via cloud-init)
- Root: disabled

---

## Vagrant Boxes

**Vagrant Cloud:** https://app.vagrantup.com/boxes/search

| Box | Provider | Command |
|-----|----------|---------|
| Ubuntu 24.04 | VirtualBox | `vagrant init ubuntu/noble64` |
| Ubuntu 22.04 | VirtualBox | `vagrant init ubuntu/jammy64` |
| Debian 12 | VirtualBox | `vagrant init debian/bookworm64` |
| Generic Ubuntu | libvirt | `vagrant init generic/ubuntu2204` |

**Default Credentials:**
- Username: `vagrant`
- Password: `vagrant`
- SSH Key: Vagrant insecure key (auto-replaced on first boot)
- Sudo: passwordless

---

## VirtualBox

**Pre-built VMs:** https://www.osboxes.org/virtualbox-images/

**Default Credentials (osboxes.org):**
- Username: `osboxes`
- Password: `osboxes.org`
- Root password: `osboxes.org`

**Ubuntu Desktop ISOs:** https://ubuntu.com/download/desktop

---

## VMware

**Pre-built VMs:** https://www.osboxes.org/vmware-images/

**VMware Marketplace:** https://marketplace.cloud.vmware.com/

**Default Credentials (osboxes.org):**
- Username: `osboxes`
- Password: `osboxes.org`

---

## Hyper-V

**Quick Create Gallery (Windows 10/11):**
- Ubuntu 24.04 LTS
- Ubuntu 22.04 LTS

Access via: Hyper-V Manager → Quick Create → Select Ubuntu

**Default Credentials:**
- Set during first boot wizard

---

## Multipass (Ubuntu VMs)

**Install:** https://multipass.run/

```bash
# Launch Ubuntu VM
multipass launch --name dev 24.04

# Shell into VM
multipass shell dev
```

**Default Credentials:**
- Username: `ubuntu`
- Password: *none* (use `multipass shell`)
- Sudo: passwordless

---

## AWS EC2 AMIs

**AMI Finder:** https://cloud-images.ubuntu.com/locator/ec2/

**Default Credentials:**
| OS | Username |
|----|----------|
| Ubuntu | `ubuntu` |
| Debian | `admin` |
| Amazon Linux | `ec2-user` |
| RHEL | `ec2-user` |
| CentOS | `centos` |

> EC2 uses SSH key pairs only. No password auth by default.

---

## Azure Images

**Marketplace:** https://azuremarketplace.microsoft.com/

**Default Credentials:**
| OS | Username |
|----|----------|
| Ubuntu | Set at creation |
| Debian | Set at creation |

Azure requires you to specify credentials during VM creation.

---

## Google Cloud (GCE)

**Public Images:** `gcloud compute images list`

**Default Credentials:**
| OS | Username |
|----|----------|
| Ubuntu | Your Google account username |
| Debian | Your Google account username |

GCE uses OS Login or project-level SSH keys.

---

## Proxmox / QEMU / KVM

**Cloud-Init Images:**
- Ubuntu: https://cloud-images.ubuntu.com/ (`.img` files)
- Debian: https://cloud.debian.org/images/cloud/

**Default Credentials:**
- Configured via cloud-init at VM creation
- No default password

---

## Docker Desktop VM

**Download:** https://www.docker.com/products/docker-desktop/

**Default Credentials:**
- N/A (managed by Docker Desktop)

---

## UTM (macOS)

**Gallery:** https://mac.getutm.app/gallery/

**Default Credentials:**
- Varies by image (check gallery page)

---

## Quick Reference Table

| Platform | Default User | Default Password |
|----------|--------------|------------------|
| Ubuntu Cloud | `ubuntu` | *(SSH key only)* |
| Debian Cloud | `debian` | *(SSH key only)* |
| Vagrant | `vagrant` | `vagrant` |
| osboxes.org | `osboxes` | `osboxes.org` |
| Multipass | `ubuntu` | *(none)* |
| AWS EC2 Ubuntu | `ubuntu` | *(SSH key only)* |
| AWS EC2 Amazon Linux | `ec2-user` | *(SSH key only)* |

---

## Security Reminder

⚠️ **Always change default credentials immediately after deployment!**

```bash
# Change password
passwd

# Disable password auth (SSH only)
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```
