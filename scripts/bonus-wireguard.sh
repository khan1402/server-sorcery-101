#!/usr/bin/env bash
# bonus-wireguard.sh - sets up a WireGuard interface on this VM.
# Only runs when provisioned with ENABLE_BONUS=true (see Vagrantfile).
#
# Scope: each VM gets its own keypair and an active wg0 interface, ready to
# encrypt traffic. Full mesh peering between all 4 VMs isn't configured here
# (see docs/architecture.md "Recommendations" for why) - this establishes
# the VPN layer itself, demonstrable via `sudo wg show`.
set -euo pipefail

echo "==> Installing WireGuard"
apt-get install -y wireguard >/dev/null

echo "==> Generating WireGuard keypair"
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
chmod 600 /etc/wireguard/privatekey

PRIVATE_KEY=$(cat /etc/wireguard/privatekey)

# Overlay address mirrors this VM's existing 192.168.56.x last octet, just
# on a separate 10.10.0.x range, so the mapping is easy to reason about.
HOSTNAME=$(hostname)
case "$HOSTNAME" in
  load-balancer) WG_IP="10.10.0.10" ;;
  web-server-1)  WG_IP="10.10.0.11" ;;
  web-server-2)  WG_IP="10.10.0.12" ;;
  app-server)    WG_IP="10.10.0.13" ;;
  *)             WG_IP="10.10.0.99" ;;
esac

cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${WG_IP}/24
ListenPort = 51820
EOF
chmod 600 /etc/wireguard/wg0.conf

echo "==> Enabling WireGuard interface"
systemctl enable --now wg-quick@wg0

echo "==> Allowing WireGuard traffic from the lab subnet"
ufw allow from 192.168.56.0/24 to any port 51820 proto udp

echo "==> [$HOSTNAME] WireGuard public key (save this to add as a peer elsewhere):"
cat /etc/wireguard/publickey

echo "==> bonus-wireguard.sh complete"
