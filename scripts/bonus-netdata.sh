#!/usr/bin/env bash
# bonus-netdata.sh - real-time performance monitoring dashboard.
# Only runs when provisioned with ENABLE_BONUS=true (see Vagrantfile).
#
# Access is restricted to the lab subnet (192.168.56.0/24), not the open
# internet - consistent with the "least exposure" design used everywhere
# else in this project. Your Windows host sits on that same subnet via
# VirtualBox's host-only adapter, so a direct browser visit works with no
# tunnel needed.
set -euo pipefail
 
echo "==> Installing Netdata (Ubuntu package - faster than the official kickstart installer)"
apt-get install -y netdata >/dev/null
 
# The Ubuntu package binds to 127.0.0.1 (localhost) by default, which means
# it's unreachable from anywhere but the VM itself - the UFW rule below is
# necessary but not sufficient without this. Bind to all interfaces instead;
# UFW is what actually controls who's allowed to reach it.
mkdir -p /etc/netdata
cat <<'EOF' > /etc/netdata/netdata.conf
[web]
	bind to = 0.0.0.0
EOF
 
# apt installs Netdata's web files owned by root, but Netdata refuses to
# serve files it doesn't itself own as a built-in security check - this
# produces "Access to file is not permitted" in the browser even though
# normal Linux file permissions would otherwise allow it. Fix ownership
# to match the user Netdata actually runs as.
chown -R netdata:netdata /usr/share/netdata/web
 
systemctl restart netdata
 
echo "==> Restricting the Netdata dashboard to the lab subnet only"
ufw allow from 192.168.56.0/24 to any port 19999 proto tcp
 
HOSTIP=$(hostname -I | awk '{print $2}')
echo "==> bonus-netdata.sh complete. View at: http://${HOSTIP}:19999"
 

