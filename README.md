# Server Sorcery 101 — Infrastructure Setup

## 1. Project Overview

A 4-VM environment simulating a small production web stack, built with Vagrant + VirtualBox:

- **load-balancer** — the only VM reachable from outside the lab network. Runs nginx as a reverse proxy.
- **web-server-1 / web-server-2** — stateless request handlers behind the load balancer.
- **app-server** — hosts the core application logic, reachable only from the web tier.

The environment is designed around the principle of **least exposure**: every VM only accepts traffic it strictly needs, from exactly the hosts that need to send it.

For the full network diagram, IP/resource table, and security-measures breakdown, see [`docs/architecture.md`](docs/architecture.md). For the running build log this project was developed from, see [`docs/notes.md`](docs/notes.md).

## 2. Repository Structure

```
server-sorcery-101/
├── Vagrantfile              # VM topology: hostnames, IPs, resources, provisioning order
├── README.md                # this file — quick start
├── .gitignore
├── scripts/
│   ├── common.sh             # baseline hardening applied to every VM
│   ├── role-load-balancer.sh # nginx reverse proxy + public-facing firewall rule
│   ├── role-web-server.sh    # placeholder web app + LB-only firewall rule
│   ├── role-app-server.sh    # placeholder core logic + web-tier-only firewall rule
│   └── bonus-fail2ban.sh     # optional, not run by default
├── validate/
│   └── check-requirements.sh # scripted version of the grading checklist
└── docs/
    ├── architecture.md       # final network diagram, IP table, security measures
    └── notes.md               # running build log — source material for the above
```

## 3. Setup & Installation

### Prerequisites
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- [Vagrant](https://developer.hashicorp.com/vagrant/downloads)
- An SSH key pair for the `devops` user:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/devops_key
  ```

### Bring the environment up
```bash
git clone <this-repo>
cd server-sorcery-101
vagrant up
```

This will, per VM, in order:
1. Provision the box and assign its static IP
2. Copy the `devops` public key onto the VM (`file` provisioner)
3. Run `scripts/common.sh` — creates the `devops` user, hardens SSH, sets up UFW, sets umask, enables auto security updates, writes `/etc/hosts` entries for name resolution
4. Run the role-specific script (`role-load-balancer.sh`, `role-web-server.sh`, or `role-app-server.sh`)

**Important — save the sudo passwords shown during setup.** Each VM gets a random local password for the `devops` user, generated fresh during provisioning and printed once to the console in a boxed block:

```
################################################################
# [load-balancer] devops sudo password (SAVE THIS, shown once): <random>
################################################################
```

SSH key auth gets you *into* a VM, but `sudo` checks a separate local password - without saving this, you can log in but won't be able to run anything with `sudo` on that VM. See [`docs/architecture.md`](docs/architecture.md) ("Sudo Password Handling") for why this exists. If you lose a password, there's no recovery - destroy and rebuild that one VM (`vagrant destroy <vm> -f && vagrant up <vm>`) to get a fresh one.

### Accessing the environment
```bash
ssh -i ~/.ssh/devops_key devops@192.168.56.10   # load-balancer
ssh -i ~/.ssh/devops_key devops@192.168.56.11   # web-server-1
ssh -i ~/.ssh/devops_key devops@192.168.56.12   # web-server-2
ssh -i ~/.ssh/devops_key devops@192.168.56.13   # app-server
```

Load balancer, from the host browser: `http://localhost:8080`

## 4. Validating the Setup

Run the scripted checklist before a review:
```bash
./validate/check-requirements.sh
```

Or check things manually — these map directly to the grading rubric:

```bash
# Hostname + resolution
hostname                                  # on each VM
ping -c 3 web-server-1                    # from any other VM

# Static IP persists after reboot
ip a
vagrant reload web-server-1 && ssh ... ip a   # confirm unchanged

# Inter-VM connectivity
ping -c 3 192.168.56.11                   # 0% packet loss expected

# devops user + sudo group
grep devops /etc/passwd
groups devops                             # -> devops : devops sudo

# Password auth disabled / key-only login
ssh devops@192.168.56.10                  # should NOT prompt for a password
ssh root@192.168.56.10                    # should be refused
ssh someoneelse@192.168.56.10             # should be refused (AllowUsers devops)

# sudo requires password (not passwordless)
sudo visudo                               # should prompt devops for their password

# Active interfaces
ip link show

# UFW status
sudo ufw status verbose

# umask
umask

# Auto security updates
cat /etc/apt/apt.conf.d/20auto-upgrades
sudo apt update && sudo apt list --upgradable
```

## 5. Bonus / Extra Functionality

- `scripts/bonus-fail2ban.sh` — optional Fail2Ban setup for SSH brute-force protection. Not wired into `vagrant up` by default; run manually on a VM, or add it as a named provisioner in the Vagrantfile if you want it to run automatically.

Recommended (not implemented) next steps — WireGuard, monitoring, TLS termination — are covered in [`docs/architecture.md`](docs/architecture.md) under "Recommendations for Future Improvements."

## 6. Challenges & Lessons Learned

See [`docs/notes.md`](docs/notes.md) for the full build log. Headline items worth knowing before a review:

- **`devops` had an SSH key but no local password.** Early on, `common.sh` created the `devops` user and installed an SSH key, but never actually set a Linux password - SSH key auth and `sudo`'s local password check are two completely separate systems, and disabling `PasswordAuthentication` in `sshd_config` has zero effect on what `sudo` checks. Fixed by generating a random password per VM at provisioning time (see "Setup & Installation" above and `docs/architecture.md`), rather than hardcoding one in the repo.
- **The umask hardening (a rubric requirement) broke web content serving as a side effect.** Once umask 027 was genuinely enforced everywhere, root-created files like the web server's `index.html` and the app server's `app.py` stopped being readable by the non-root processes (`www-data` for nginx, `devops` for the systemd service) that needed to serve/run them - producing a live `403 Forbidden` through the load balancer despite the nginx config itself being correct. Fixed with explicit `chown`/`chmod` on just those specific files, rather than loosening the umask policy itself. Traced end-to-end via `curl -v`, the nginx error log, and `ls -la` on the actual file - full debugging trail in `docs/notes.md` (Day 5).
- **`AllowUsers devops` + UFW's subnet restriction together permanently lock out Vagrant's own NAT-based access** (`vagrant ssh`, `vagrant provision`, `vagrant reload`) once `common.sh` has run on a VM - by design, not a bug. Any future admin access has to go through `ssh devops@<private-ip>` directly, and any script changes require a full `vagrant destroy` + `vagrant up` rather than live reprovisioning.
- **UFW enabled before the SSH allow rule exists** can lock you out entirely - `common.sh` adds the SSH rule *before* `ufw --force enable` for exactly this reason.
- **Two NICs per VM, both in use** - `eth0` (Vagrant/VirtualBox NAT, used for provisioning) and `eth1` (the private network, your static IP). Worth explaining explicitly rather than it looking like an oversight during review.
- **VMs occasionally time out on first boot after a cold `vagrant halt` / `vagrant up` cycle**, even with `boot_timeout` raised to 900s - resolved every time by destroying and rebuilding just that one VM (`vagrant destroy <vm> -f && vagrant up <vm>`), sometimes needing 2-3 attempts. Not fully root-caused, but consistently fixable.
