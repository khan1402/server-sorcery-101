#!/usr/bin/env bash
# bonus-fail2ban.sh - OPTIONAL. Not wired into the Vagrantfile by default.
# Run manually on any VM (e.g. `vagrant ssh load-balancer` then paste this,
# or `vagrant upload` it and run with sudo) to add brute-force protection.
set -euo pipefail

apt-get install -y fail2ban >/dev/null

cat <<'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = 22
logpath = %(sshd_log)s
backend = systemd
EOF

systemctl enable --now fail2ban
fail2ban-client status sshd

echo "==> fail2ban installed. Check status any time with:"
echo "    sudo fail2ban-client status sshd"
