#!/bin/bash
# Bonus scenario: a DIFFERENT failure mode than the app-bug demo - here,
# nothing is broken, but "a teammate changed something" and you need to
# find out who/what/when. Run this yourself (not part of any SSM deploy)
# to generate a harmless, reversible tagging change that stands in for a
# real config change (e.g. an SG rule edit), then look it up in CloudTrail.
#
# Safe by design: only adds/updates an EC2 tag - no security group, IAM,
# or instance state is touched, so there is nothing to roll back that
# affects the running demo.
set -euo pipefail

INSTANCE_ID="${1:?Usage: cloudtrail-scenario.sh <instance-id>}"
REGION="${AWS_REGION:-us-east-1}"

echo "Simulating a config change: tagging the instance (stand-in for 'someone edited the security group')..."
aws ec2 create-tags --region "$REGION" \
  --resources "$INSTANCE_ID" \
  --tags "Key=LastTouchedBy,Value=on-call-teammate-$(date +%s)"

echo "Change made. CloudTrail typically takes up to ~5-15 minutes to surface a new"
echo "management event in lookup-events - for the talk, run this part ahead of time"
echo "(e.g. right after starting the instance), then look it up live during Part 5:"
echo
echo "  aws cloudtrail lookup-events --region $REGION \\"
echo "    --lookup-attributes AttributeKey=ResourceName,AttributeValue=$INSTANCE_ID \\"
echo "    --max-results 5"
echo
echo "That returns the CreateTags event with the calling identity (who), the source"
echo "IP, and the timestamp (when) - the same technique works for any management"
echo "event: a security group edit, an IAM policy change, an instance stop/start."
