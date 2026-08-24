# Build Notes

Running log kept while building the environment. Messy on purpose — this is
source material for `architecture.md` and the README's "Challenges" section,
not a polished document. Add an entry every time you make a real decision,
hit a problem, or change your mind about something.

Suggested format per entry:
```
## Day N — <what you were working on>
**Did:** what you actually did
**Problem:** what broke or was unclear (if anything)
**Fix / decision:** how you resolved it, or what you decided and why
```

---

## Day 0 — Windows toolchain setup (VirtualBox, Vagrant, WSL2, Git)

**Did:** Installed VirtualBox 7.2.16 and Vagrant 2.4.9 on Windows. Confirmed
VT-x enabled in BIOS. Installed Git for Windows (Git Credential Manager,
LF line endings on checkout to avoid breaking shell scripts, main as
default branch name). Set up VS Code with a local (non-WSL) PowerShell
terminal as the default profile.

**Problem:** My laptop already had WSL2 (Ubuntu) set up and in regular use.
WSL2 depends on Windows' Hyper-V/VirtualMachinePlatform feature, and
VirtualBox has historically conflicted with Hyper-V being active — the two
compete for the same hardware virtualization (VT-x). Initially disabled
Hyper-V entirely for VirtualBox, which broke WSL2 and VS Code's
Remote-WSL connection. Also discovered my actual project folder only
existed inside the WSL filesystem, not on the Windows side where Vagrant
needed it — had to copy it out via `\\wsl.localhost\Ubuntu\...` and flatten
an accidental nested-folder copy.

**Fix / decision:** Re-enabled `VirtualMachinePlatform` (keeping the full
`Microsoft-Hyper-V-All` role disabled) and tested with a disposable Vagrant
VM. VirtualBox 7.2 booted it in ~20 seconds — full native speed, not the
slower Hyper-V-fallback mode some older guides warn about. Decided to run
one unified environment: WSL2 stays enabled for future projects (Ansible in
P3 needs a real Linux control node), VirtualBox/Vagrant run directly from
Windows PowerShell (not through WSL), avoiding a dual-boot workaround that
would've made Ansible unreachable later anyway.

---

## Day 1 — VM topology & networking

**Did:** Designed a 4-VM topology in the `Vagrantfile`: `load-balancer`
(192.168.56.10, 2 vCPU/1GB), `web-server-1`/`web-server-2` (.11/.12, 1
vCPU/1GB each), `app-server` (.13, 2 vCPU/2GB), all on a VirtualBox
host-only private network (192.168.56.0/24) with static IPs. Only
`load-balancer` gets a forwarded port to the host (8080→80), so it's the
only VM reachable from outside the private network — enforced at the
network layer, not just the firewall. Resource split: load balancer gets
extra CPU (connection-handling is CPU-bound), app server gets extra RAM
(business logic/caching is memory-bound), web servers stay lean since
there are two of them.

**Problem:** None yet at the design stage — issues showed up once VMs
actually ran (see later entries).

**Fix / decision:** Used static `/etc/hosts` entries on every VM (written
by `common.sh`) for hostname resolution between VMs, since there's no DNS
server in this lab network.

---

## Day 2 — devops user & SSH hardening

**Did:** `common.sh` creates the `devops` user, adds it to `sudo`, installs
the SSH public key, then hardens `sshd_config`: `PermitRootLogin no`,
`PasswordAuthentication no`, `AllowUsers devops`.

**Problem:** Vagrant's own SSH access (used internally by `vagrant ssh` /
`vagrant provision`, connecting as the `vagrant` user through a NAT port
forward) gets locked out by this same hardening — `AllowUsers devops`
rejects the `vagrant` user, and UFW (see Day 3) only accepts SSH from the
private subnet, not the NAT path Vagrant uses. Confirmed this for real
later: after the first successful `vagrant up`, `vagrant ssh load-balancer`
failed with `Connection reset` — traced it with `ssh -vvv` directly against
the NAT-forwarded key/port and confirmed the reset happens during the
identification exchange, consistent with UFW dropping it before SSH even
gets to check the username.

**Fix / decision:** Accepted this as by-design, not a bug — the whole point
of the hardening is that only `devops`, over the private network, can get
in. Documented that `vagrant ssh`/`vagrant provision` become unusable once
`common.sh` has run on a VM; any future admin access has to go through
`ssh devops@<private-ip>`, and any script changes require a full
`vagrant destroy` + `vagrant up` rather than live reprovisioning.

---

## Day 3 — UFW & firewall rules

**Did:** `common.sh` sets a default-deny UFW baseline (`ufw default deny
incoming`, `ufw default allow outgoing`) with an SSH allow rule scoped to
`192.168.56.0/24` only. Role scripts add their own rules on top:
`load-balancer` opens port 80 to everyone (the one public-facing
exception), web servers only accept port 80 from the load balancer's IP,
`app-server` only accepts port 3000 from the web-tier subnet.

**Problem:** Order matters — the SSH allow rule has to exist *before*
`ufw --force enable` runs, or you lock yourself out entirely the moment
the firewall activates.

**Fix / decision:** Wrote the SSH allow rule ahead of the `ufw enable` line
in `common.sh` specifically to avoid that trap. Also confirmed (see Day 2)
that this same subnet restriction is what blocks Vagrant's own NAT-based
access after provisioning — intentional, but worth explaining clearly
during review since it looks like a Vagrant problem at first glance and is
actually the firewall working correctly.

---

## Day 4 — umask, auto-updates, sudo password gap, boot timeout

**Did:** Set `UMASK 027` system-wide via `/etc/login.defs` and a
`profile.d` script. Installed and enabled `unattended-upgrades` with both
`Update-Package-Lists` and `Unattended-Upgrade` turned on. Ran the first
full `vagrant up` across all 4 VMs — provisioning completed with no
errors, `groups devops` correctly showed `devops sudo`.

**Problem:** SSHed in as `devops` (worked instantly, no password — key
auth confirmed working) but `sudo whoami` rejected every attempt. Turned
out `common.sh` only ever ran `useradd` and installed the SSH key for
`devops` — it never actually set a Linux password with `passwd`/
`chpasswd`. SSH key auth and sudo's local password check are two
completely separate systems; disabling `PasswordAuthentication` in
`sshd_config` has zero effect on what `sudo` checks locally. Tried
`vagrant ssh` as a workaround to fix it live — blocked by the same
UFW/AllowUsers restriction from Day 2/3, confirming that path really is
dead once hardening has run. Separately, on the rebuild attempt, hit a
`Timed out while waiting for the machine to boot` error even though the
VM's own console (checked directly in VirtualBox Manager) showed it had
booted cleanly to a login prompt — this particular Ubuntu cloud image uses
`cloud-init` on first boot, which occasionally takes longer than Vagrant's
default 300-second `boot_timeout`.

**Fix / decision:** Updated `common.sh` to generate a random password per
VM with `openssl rand -base64 12`, set it via `chpasswd`, and print it once
to the provisioning console output — never hardcoded or committed to git,
since that would be a real secret sitting in a public repo. Raised
`config.vm.boot_timeout` to 600 in the `Vagrantfile` to give cloud-init
more room. Destroyed and rebuilt all 4 VMs from the fixed script rather
than patching the already-broken ones by hand — treating VMs as disposable
felt like the actual point of infrastructure-as-code rather than a
workaround. Re-verified after rebuild: `sudo whoami` correctly prompted
for the new password and returned `root`.

---

<!-- Add more entries as you go. Don't delete failed attempts - they're the
     most useful part of this file when you write up "challenges & lessons
     learned" later. -->
