#!/bin/bash
# One-time instance setup. Run once via:
#   aws ssm send-command --instance-ids <id> --document-name AWS-RunShellScript \
#     --parameters commands="$(cat bootstrap.sh)"
set -euo pipefail

APP_USER=pocaws
APP_DIR=/opt/pocaws

if ! id "$APP_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"
chmod 750 "$APP_DIR"

touch "$APP_DIR/app.env"
chown "$APP_USER:$APP_USER" "$APP_DIR/app.env"
chmod 600 "$APP_DIR/app.env"

cat > /etc/systemd/system/pocaws.service <<'UNIT'
[Unit]
Description=poc-aws Spring Boot API
After=network.target

[Service]
User=pocaws
Group=pocaws
WorkingDirectory=/opt/pocaws
EnvironmentFile=-/opt/pocaws/app.env
ExecStart=/usr/bin/java -jar /opt/pocaws/app.jar
SuccessExitStatus=143
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/pocaws

[Install]
WantedBy=multi-user.target
UNIT

dnf install -y java-17-amazon-corretto-headless

systemctl daemon-reload
systemctl enable pocaws

echo "Bootstrap complete. Service enabled but not started (no jar deployed yet)."
