# Architecture

Final-state documentation of the Server Sorcery 101 environment. For the day-to-day
build log (what broke, what changed, why), see `notes.md` in this same folder.

## Network Diagram

```
                         Internet / Host Browser
                                  │
                                  │  :8080 -> :80 (forwarded port)
                                  ▼
                       ┌─────────────────────┐
                       │   load-balancer      │
                       │   192.168.56.10       │
                       │   nginx (reverse      │
                       │   proxy, round-robin) │
                       └──────────┬────────────┘
                                  │ 192.168.56.0/24, port 80 only
                    ┌─────────────┴─────────────┐
                    ▼                            ▼
         ┌────────────────────┐       ┌────────────────────┐
         │  web-server-1       │       │  web-server-2       │
         │  192.168.56.11       │       │  192.168.56.12       │
         │  nginx (web app)     │       │  nginx (web app)     │
         └──────────┬───────────┘       └──────────┬───────────┘
                    │        192.168.56.0/24, port 3000 only     │
                    └───────────────────┬─────────────────────────┘
                                         ▼
                              ┌────────────────────┐
                              │   app-server         │
                              │   192.168.56.13       │
                              │   core app logic      │
                              │   (port 3000)         │
                              └────────────────────┘
```

## IP & Resource Table

| VM | Hostname | Static IP | CPU | RAM | Exposed to |
|---|---|---|---|---|---|
| Load Balancer | `load-balancer` | 192.168.56.10 | 2 vCPU | 1 GB | Host browser (:8080→:80) + lab subnet |
| Web Server 1 | `web-server-1` | 192.168.56.11 | 1 vCPU | 1 GB | Load balancer only (port 80) |
| Web Server 2 | `web-server-2` | 192.168.56.12 | 1 vCPU | 1 GB | Load balancer only (port 80) |
| App Server | `app-server` | 192.168.56.13 | 2 vCPU | 2 GB | Web tier only (port 3000) |

**Resource reasoning:**
- **Load balancer** gets extra CPU, not RAM — it's proxying connections and (eventually) terminating TLS, both CPU-bound tasks, but it holds no application state.
- **Web servers** are deliberately light — they're stateless and horizontally scaled (two of them), so each one only needs to comfortably run nginx.
- **App server** gets the most RAM — in a real deployment this is where in-memory caches, DB connection pools, and business logic would live, all memory-hungry.

**Interfaces:** every VM has two NICs — `eth0` (Vagrant/VirtualBox's own NAT interface, used for provisioning and box management) and `eth1` (the private network, carrying the static IP above). Both are actively used; nothing is disabled because nothing is unused.

## Security Measures Implemented

| Measure | Where | Why |
|---|---|---|
| Root SSH login disabled | `scripts/common.sh` | Removes the single highest-value SSH target |
| Password auth disabled, key-only | `scripts/common.sh` | Eliminates brute-force password guessing entirely |
| Only `devops` may SSH in | `scripts/common.sh` (`AllowUsers`) | No other account is a viable SSH entry point |
| `devops` sudo requires password | `scripts/common.sh` | Compromised SSH key alone isn't enough for root actions |
| UFW default-deny incoming | `scripts/common.sh` | Nothing is reachable unless explicitly allowed |
| SSH only from lab subnet | `scripts/common.sh` | SSH is never exposed to the open internet |
| Load balancer = only public entry point | `scripts/role-load-balancer.sh` | Minimizes attack surface; backend tiers have zero direct exposure |
| Web tier reachable only from LB | `scripts/role-web-server.sh` | Prevents bypassing the load balancer |
| App tier reachable only from web subnet | `scripts/role-app-server.sh` | Core logic is never directly reachable, even from the LB |
| umask 027 | `scripts/common.sh` | New files aren't world-readable/writable by default |
| Unattended security upgrades | `scripts/common.sh` | Known vulnerabilities get patched without manual intervention |

## Sudo Password Handling

SSH key authentication and `sudo`'s local password check are two separate
systems — installing an SSH key for `devops` gets you *into* a VM, but says
nothing about whether `sudo` will accept anything once you're there. Early
in the build, `common.sh` created `devops` and gave it sudo group
membership but never actually set a Linux password, so `sudo` had nothing
to authenticate against at all — see `notes.md` (Day 4) for how this was
found and fixed.

**How it's set up now:** `common.sh` generates a random password per VM
with `openssl rand -base64 12`, applies it with `chpasswd`, and prints it
once to the `vagrant up` console output in a clearly marked block:

```
################################################################
# [load-balancer] devops sudo password (SAVE THIS, shown once): <random>
################################################################
```

**Why generated, not hardcoded:** a fixed password sitting in a script
committed to a public repo would be a real credential leak the moment the
repo is pushed. Generating it fresh per VM, per provisioning run, and only
ever displaying it locally in the operator's own terminal keeps a real
password requirement (satisfying the "sudo is password-protected" rubric
item) without ever putting a secret in git history.

**Practical implication:** these passwords only exist for the lifetime of
a given VM. Every `vagrant destroy` + `vagrant up` generates fresh ones —
old passwords written down from a previous build won't work after a
rebuild, and that's expected, not a bug.

## Recommendations for Future Improvements

- **TLS termination** at the load balancer (Let's Encrypt via certbot, or self-signed for the lab)
- **WireGuard** to encrypt the private network traffic itself, not just restrict who can reach it
- **Netdata or Prometheus + Grafana** for real-time / historical resource monitoring
- **Ansible** to replace the shell-script provisioners as the environment grows — easier to keep idempotent
- **Centralized logging** so a compromised host's own logs can't be tampered with in place
