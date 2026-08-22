#!/usr/bin/env bash
# role-web-server.sh - a simple nginx instance standing in for "the web app".
# Only the load balancer is allowed to reach port 80 here - nobody else,
# and definitely not the outside world.
set -euo pipefail

echo "==> Installing nginx (placeholder web app)"
apt-get install -y nginx >/dev/null

HOST=$(hostname)
cat <<EOF > /var/www/html/index.html
<html><body><h1>Hello from ${HOST}</h1></body></html>
EOF

systemctl restart nginx
systemctl enable nginx

echo "==> Restricting port 80 to the load balancer only"
ufw allow from 192.168.56.10 to any port 80 proto tcp

echo "==> role-web-server.sh complete"
