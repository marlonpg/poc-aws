#!/bin/bash
# One-time shared setup for the 3-tier demo (orchestrator -> demo-app ->
# demo-app-db): Python + shared pip packages, the CloudWatch agent (one log
# file per service), and the X-Ray daemon (one daemon serves all 3 services
# on this single instance). Run this once via SSM before deploying any of
# the three services - their own deploy.sh scripts assume this already ran.
#
# This script takes no inputs, so it can be sent as-is (no jq needed):
#
#   aws ssm send-command --instance-ids <instance_id> \
#     --document-name AWS-RunShellScript \
#     --parameters commands="$(cat demo-common/bootstrap-common.sh)" \
#     --output text --query 'Command.CommandId'
set -euo pipefail

APP_USER=pocaws-demo

if ! id "$APP_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

dnf install -y python3 python3-pip amazon-cloudwatch-agent
pip3 install --quiet flask requests aws-xray-sdk

# --- X-Ray daemon (receives trace segments on 127.0.0.1:2000/udp from all
# three services and forwards them to the X-Ray API) ---
if ! systemctl list-unit-files | grep -q '^xray.service'; then
  curl -so /tmp/xray.rpm https://s3.us-east-1.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-3.x.rpm
  dnf install -y /tmp/xray.rpm
  rm -f /tmp/xray.rpm
fi
systemctl enable xray
systemctl restart xray

# --- CloudWatch agent: one log file per service, one log group each ---
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/pocaws-orchestrator/app.log",
            "log_group_name": "/aws/ec2/demo-orchestrator",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/opt/pocaws-demo/app.log",
            "log_group_name": "/aws/ec2/demo-app",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/opt/pocaws-demo-db/app.log",
            "log_group_name": "/aws/ec2/demo-app-db",
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

echo "Shared bootstrap complete: pip packages, X-Ray daemon, and CloudWatch agent (3 log groups) are ready."
