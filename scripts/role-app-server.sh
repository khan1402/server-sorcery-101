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
# Same umask side effect as role-web-server.sh: this file is created by
# root under the global 027 umask, but the systemd service below runs it
# as User=devops - without this fix, devops can't read/execute a file it
# doesn't own or share a group with, and the service silently crash-loops
# (systemctl enable --now reports success even if the process then fails).
chown devops:devops /opt/app/app.py
chmod 750 /opt/app/app.py

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

