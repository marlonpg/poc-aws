#!/bin/bash
# Run via SSM on every deploy. Expects S3_BUCKET and S3_KEY env vars,
# passed in as SSM RunCommand parameters by the GitHub Actions workflow.
set -euo pipefail

APP_DIR=/opt/pocaws
JAR_PATH="$APP_DIR/app.jar"

: "${S3_BUCKET:?S3_BUCKET not set}"
: "${S3_KEY:?S3_KEY not set}"

aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" "$JAR_PATH.new"
chown pocaws:pocaws "$JAR_PATH.new"
mv "$JAR_PATH.new" "$JAR_PATH"

systemctl restart pocaws

# Wait for the app to come up and self-check before declaring success.
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/actuator/health >/dev/null; then
    echo "Deploy successful, app is healthy."
    exit 0
  fi
  sleep 1
done

echo "Deploy failed: app did not become healthy within 30s" >&2
journalctl -u pocaws --no-pager -n 50 >&2
exit 1
