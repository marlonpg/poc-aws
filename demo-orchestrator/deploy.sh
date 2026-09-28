#!/bin/bash
# Deploy/redeploy demo-orchestrator (the public tier - calls demo-app on
# 127.0.0.1:8081). Requires demo-common/bootstrap-common.sh to have run
# once already on this instance, and demo-app to already be deployed
# (deploy it first so this tier has something to call).
#
# AWS-RunShellScript only accepts a "commands" array, so S3_BUCKET/S3_KEY
# have to be baked in via jq (a literal `,S3_BUCKET=...` on send-command is
# NOT a real parameter and will fail to parse):
#
#   jq -n --rawfile script deploy.sh --arg bucket "<bucket>" --arg key "demo-orchestrator/app.py" \
#     '{commands: (["export S3_BUCKET=" + $bucket, "export S3_KEY=" + $key] + ($script | split("\n")))}' \
#     > deploy-params.json
#
#   aws ssm send-command --instance-ids <instance_id> \
#     --document-name AWS-RunShellScript \
#     --parameters file://deploy-params.json \
#     --output text --query 'Command.CommandId'
#
# Upload app.py first: aws s3 cp app.py s3://<bucket>/demo-orchestrator/app.py
set -euo pipefail

APP_USER=pocaws-demo
APP_DIR=/opt/pocaws-orchestrator

: "${S3_BUCKET:?S3_BUCKET not set}"
: "${S3_KEY:?S3_KEY not set}"

mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"
chmod 750 "$APP_DIR"

aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" "$APP_DIR/app.py"
chown "$APP_USER:$APP_USER" "$APP_DIR/app.py"

cat > /etc/systemd/system/pocaws-orchestrator.service <<'UNIT'
[Unit]
Description=poc-aws demo orchestrator Flask API (lightning talk, public)
After=network.target

[Service]
User=pocaws-demo
Group=pocaws-demo
WorkingDirectory=/opt/pocaws-orchestrator
ExecStart=/usr/bin/python3 /opt/pocaws-orchestrator/app.py
StandardOutput=append:/opt/pocaws-orchestrator/app.log
StandardError=append:/opt/pocaws-orchestrator/app.log
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/pocaws-orchestrator

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable pocaws-orchestrator
systemctl restart pocaws-orchestrator

sleep 2
curl -sf http://127.0.0.1:8080/health && echo "demo-orchestrator is up."
