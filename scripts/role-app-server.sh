#!/usr/bin/env bash
# role-app-server.sh - stand-in "core application logic" service on port 3000.
# Only the web servers (never the load balancer, never the outside world)
# are allowed to reach it.
set -euo pipefail

echo "==> Installing Python (placeholder app runtime)"
apt-get install -y python3 >/dev/null

mkdir -p /opt/app
cat <<'EOF' > /opt/app/app.py
import http.server, socketserver, socket

PORT = 3000

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Hello from app-server ({socket.gethostname()})".encode())

with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

cat <<'EOF' > /etc/systemd/system/placeholder-app.service
[Unit]
Description=Placeholder core application service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always
User=devops

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now placeholder-app

echo "==> Restricting port 3000 to the web tier subnet only"
ufw allow from 192.168.56.0/24 to any port 3000 proto tcp

echo "==> role-app-server.sh complete"
