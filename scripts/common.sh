#!/usr/bin/env bash
# common.sh - baseline hardening applied identically to every VM.
# Run as root via Vagrant's shell provisioner.
set -euo pipefail

THIS_HOST="$1"

echo "==> [$THIS_HOST] Updating package index"
apt-get update -qq

echo "==> [$THIS_HOST] Writing static /etc/hosts entries for name resolution"
# No DNS server in this lab network, so every VM gets a static hosts file.
# This is what makes 'ping <hostname>' work between VMs.
cat <<'EOF' >> /etc/hosts

# --- server-sorcery lab network ---
192.168.56.10 load-balancer
192.168.56.11 web-server-1
192.168.56.12 web-server-2
192.168.56.13 app-server
EOF

echo "==> [$THIS_HOST] Creating devops user"
if ! id devops &>/dev/null; then
  useradd -m -s /bin/bash devops
fi
usermod -aG sudo devops

echo "==> [$THIS_HOST] Installing SSH key for devops"
mkdir -p /home/devops/.ssh
cp /tmp/devops_key.pub /home/devops/.ssh/authorized_keys
chown -R devops:devops /home/devops/.ssh
chmod 700 /home/devops/.ssh
chmod 600 /home/devops/.ssh/authorized_keys

echo "==> [$THIS_HOST] Sudo access for devops (password-protected, not passwordless)"
cat <<'EOF' > /etc/sudoers.d/devops
devops ALL=(ALL) ALL
EOF
chmod 440 /etc/sudoers.d/devops
visudo -cf /etc/sudoers.d/devops

echo "==> [$THIS_HOST] Allowing password-free read-only UFW status checks only"
# Everything else devops does with sudo (visudo, passwd, actually changing
# firewall rules, etc.) still requires a password - this ONE narrowly-scoped
# exception exists so validate/check-requirements.sh can verify UFW is
# active over a non-interactive SSH session, where there's no way to type
# a password in the first place.
cat <<'EOF' > /etc/sudoers.d/devops-readonly
devops ALL=(ALL) NOPASSWD: /usr/sbin/ufw status, /usr/sbin/ufw status verbose
EOF
chmod 440 /etc/sudoers.d/devops-readonly
visudo -cf /etc/sudoers.d/devops-readonly

echo "==> [$THIS_HOST] Setting a random local password for devops (needed for sudo)"
# SSH key auth gets you INTO the box, but sudo checks a separate LOCAL password.
# We never hardcode this in the repo - generate one fresh per VM and print it
# once here so you can copy it down from the `vagrant up` output.
DEVOPS_PASSWORD=$(openssl rand -base64 12)
echo "devops:${DEVOPS_PASSWORD}" | chpasswd
echo ""
echo "    ################################################################"
echo "    # [$THIS_HOST] devops sudo password (SAVE THIS, shown once): ${DEVOPS_PASSWORD}"
echo "    ################################################################"
echo ""

echo "==> [$THIS_HOST] Hardening SSH daemon"
SSHD_CONFIG=/etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG"
if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
  echo "AllowUsers devops" >> "$SSHD_CONFIG"
fi
sshd -t   # validate config before restarting, fail loudly if broken
systemctl restart ssh

echo "==> [$THIS_HOST] Setting secure umask (027: owner rwx, group rx, others none)"
sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs
cat <<'EOF' > /etc/profile.d/99-umask.sh
umask 027
EOF
chmod 644 /etc/profile.d/99-umask.sh
# profile.d only applies to interactive login shells. Non-interactive SSH
# commands (e.g. `ssh host "cmd"`, used by validate/check-requirements.sh)
# skip it entirely and fall back to PAM's default. Ubuntu ships a default
# `session optional pam_umask.so` line in common-session with NO umask=
# parameter, which was tripping up a naive "does pam_umask exist" check -
# we need to make sure OUR value is actually set, not just that some
# pam_umask line is present.
if grep -q "pam_umask.so umask=" /etc/pam.d/common-session; then
  sed -i 's/pam_umask\.so umask=[0-9]*/pam_umask.so umask=0027/' /etc/pam.d/common-session
elif grep -q "pam_umask.so" /etc/pam.d/common-session; then
  sed -i 's/pam_umask\.so/pam_umask.so umask=0027/' /etc/pam.d/common-session
else
  echo "session optional pam_umask.so umask=0027" >> /etc/pam.d/common-session
fi

echo "==> [$THIS_HOST] Installing and enabling UFW (default-deny baseline)"
apt-get install -y ufw >/dev/null
ufw default deny incoming
ufw default allow outgoing
# SSH only from inside our lab subnet, never from the open internet
ufw allow from 192.168.56.0/24 to any port 22 proto tcp
ufw logging on
ufw --force enable

echo "==> [$THIS_HOST] Enabling unattended security updates"
apt-get install -y unattended-upgrades apt-listchanges >/dev/null
cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

echo "==> [$THIS_HOST] common.sh complete"
