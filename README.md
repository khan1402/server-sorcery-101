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

- **`AllowUsers devops` + mid-provision `systemctl restart ssh`:** Vagrant's own provisioning connection uses the `vagrant` user. Restarting sshd after locking logins down to `devops` doesn't kill the *already-open* session Vagrant is using for that run, but it will break `vagrant provision` on a second run, since Vagrant reconnects as `vagrant` and gets rejected.
- **UFW enabled before the SSH allow rule exists** can lock you out entirely — `common.sh` adds the SSH rule *before* `ufw --force enable` for exactly this reason.
- **Two NICs per VM, both in use** — `eth0` (Vagrant/VirtualBox NAT, used for provisioning) and `eth1` (the private network, your static IP). Worth explaining explicitly rather than it looking like an oversight during review.
