#!/bin/bash
# One-time setup + deploy for the lightning-talk demo app.
# Run via SSM against the existing instance (same auth/instance role as the
# rest of this repo - no new IAM setup needed).
#
# AWS-RunShellScript only accepts a "commands" parameter, so S3_BUCKET/
# S3_KEY have to be baked into that array (a literal `,S3_BUCKET=...` on
# send-command is NOT a real parameter and will fail to parse). Build the
# params file with jq:
#
#   jq -n --rawfile script deploy.sh --arg bucket "<bucket>" --arg key "demo-app/app.py" \
#     '{commands: (["export S3_BUCKET=" + $bucket, "export S3_KEY=" + $key] + ($script | split("\n")))}' \
#     > deploy-params.json
#
#   aws ssm send-command --instance-ids <instance_id> \
#     --document-name AWS-RunShellScript \
#     --parameters file://deploy-params.json \
#     --output text --query 'Command.CommandId'
#
# Upload app.py first:
#   aws s3 cp app.py s3://<bucket>/demo-app/app.py
set -euo pipefail

APP_USER=pocaws-demo
APP_DIR=/opt/pocaws-demo

: "${S3_BUCKET:?S3_BUCKET not set}"
: "${S3_KEY:?S3_KEY not set}"

if ! id "$APP_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"
chmod 750 "$APP_DIR"

aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" "$APP_DIR/app.py"
chown "$APP_USER:$APP_USER" "$APP_DIR/app.py"

cat > /etc/systemd/system/pocaws-demo.service <<'UNIT'
[Unit]
Description=poc-aws demo Flask API (lightning talk)
After=network.target

[Service]
User=pocaws-demo
Group=pocaws-demo
WorkingDirectory=/opt/pocaws-demo
ExecStart=/usr/bin/python3 /opt/pocaws-demo/app.py
StandardOutput=append:/opt/pocaws-demo/app.log
StandardError=append:/opt/pocaws-demo/app.log
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/pocaws-demo

[Install]
WantedBy=multi-user.target
UNIT

dnf install -y python3 python3-pip amazon-cloudwatch-agent
pip3 install --quiet flask

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/pocaws-demo/app.log",
            "log_group_name": "/aws/ec2/demo-app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl daemon-reload
systemctl enable pocaws-demo
systemctl restart pocaws-demo

sleep 2
curl -sf http://localhost:8080/health && echo "Demo app is up."
