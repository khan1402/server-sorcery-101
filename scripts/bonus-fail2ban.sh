#!/usr/bin/env bash
# bonus-fail2ban.sh - Fail2Ban intrusion prevention for SSH brute-force
# protection. Only runs when provisioned with ENABLE_BONUS=true (see
# Vagrantfile) - does not affect the default `vagrant up` behavior.
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
 
# Give the socket a moment to come up before querying it - checking status
# immediately after `enable --now` can race the service's own startup.
for i in $(seq 1 10); do
  if fail2ban-client status sshd &>/dev/null; then
    break
  fi
  sleep 1
done
fail2ban-client status sshd
 
echo "==> fail2ban installed. Check status any time with:"
echo "    sudo fail2ban-client status sshd"
 