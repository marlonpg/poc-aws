# Running this project

Operational commands for the 3-tier lightning-talk demo and its Terraform
(`infra/`). All commands assume you're in the repo root unless a `cd` is
shown. Requires `aws` CLI, `terraform`, and `jq`.

AWS auth: the `default` CLI profile is `pocaws-admin` (a scoped IAM user,
not root) - no `--profile` flag needed on any command below.

## Architecture

```
client -> demo-orchestrator (:8080, public) -> demo-app (:8081, localhost) -> demo-app-db (:8082, localhost, sqlite)
```

All three run as separate systemd services on the same existing EC2
instance (`i-02493c4d817d45bf4`), under the same `pocaws-demo` system user.
Only `demo-orchestrator` is reachable from outside (port 8080, security
group already scoped to your IP) - the other two bind `127.0.0.1` and are
unreachable regardless of security group rules. `?break=true` on
`demo-orchestrator`'s `/api/orders` propagates all the way down to
`demo-app-db`, where the actual simulated failure happens.

## One-time account setup (already done - reference only)

This created the scoped IAM user used for everything else, so root doesn't
touch AWS day-to-day:

```
aws iam create-user --user-name pocaws-admin --tags Key=Project,Value=pocaws

aws iam create-policy --policy-name pocaws-terraform-iam \
  --description "Scoped IAM permissions for pocaws terraform, no root needed" \
  --policy-document file://path/to/policy.json   # see infra/README.md for the policy body

aws iam attach-user-policy --user-name pocaws-admin \
  --policy-arn arn:aws:iam::<account_id>:policy/pocaws-terraform-iam
aws iam attach-user-policy --user-name pocaws-admin \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# Generate a key for it, then configure a profile with it (run these two
# yourself - the secret should never be pasted into a chat/AI session):
aws iam create-access-key --user-name pocaws-admin
aws configure --profile pocaws

# Deactivate the old root key (find its id first with `aws iam list-access-keys`):
aws iam update-access-key --access-key-id <root-key-id> --status Inactive

# Point default at pocaws-admin's creds instead of root, without ever
# printing the secret to the terminal:
aws configure set aws_access_key_id "$(aws configure get aws_access_key_id --profile pocaws)" --profile default
aws configure set aws_secret_access_key "$(aws configure get aws_secret_access_key --profile pocaws)" --profile default
aws configure set region us-east-1 --profile default
```

## Start / stop the instance

The instance is stopped between sessions to save cost. Start it before
doing anything else:

```
aws ec2 start-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4
aws ec2 wait instance-running --region us-east-1 --instance-ids i-02493c4d817d45bf4

# wait for SSM agent to register (usually <1 min):
aws ssm describe-instance-information --region us-east-1 \
  --filters "Key=InstanceIds,Values=i-02493c4d817d45bf4" \
  --query 'InstanceInformationList[0].PingStatus'
```

Get its current public IP (changes on every start/stop):
```
aws ec2 describe-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

When done:
```
aws ec2 stop-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4
```

## If your IP address has changed

The security group only allows port 8080 (the orchestrator) from
`admin_cidr` in `infra/terraform.tfvars`. Check your current IP and update
it if needed:

```
curl https://checkip.amazonaws.com

# edit infra/terraform.tfvars: admin_cidr = "<new-ip>/32"

cd infra
terraform apply
cd ..
```

## Apply/update the Terraform infra

```
cd infra
terraform plan    # review: should never show unexpected destroys
terraform apply
cd ..
```

## Shared setup (run once per instance lifetime)

Installs Python, the shared pip packages (Flask, requests, aws-xray-sdk),
the CloudWatch agent (configured for all 3 log files), and the X-Ray
daemon. Needs re-running only if the instance is replaced - a stop/start
doesn't lose any of this since it's on the instance's root volume.

```
CMD_ID=$(aws ssm send-command --region us-east-1 \
  --instance-ids i-02493c4d817d45bf4 \
  --document-name AWS-RunShellScript \
  --parameters commands="$(cat demo-common/bootstrap-common.sh)" \
  --output text --query 'Command.CommandId')

aws ssm get-command-invocation --region us-east-1 \
  --command-id "$CMD_ID" --instance-id i-02493c4d817d45bf4 \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'
```

## Deploy / redeploy a service

Same command for first deploy and redeploys - each `deploy.sh` is
idempotent. **Deploy in this order the first time** (db, then app, then
orchestrator) since each tier calls the one before it:

```
BUCKET=$(terraform -chdir=infra output -raw artifact_bucket_name)

deploy_service() {
  local service="$1"   # demo-app-db | demo-app | demo-orchestrator
  cd "$service"
  aws s3 cp app.py "s3://$BUCKET/$service/app.py"

  jq -n --rawfile script deploy.sh --arg bucket "$BUCKET" --arg key "$service/app.py" \
    '{commands: (["export S3_BUCKET=" + $bucket, "export S3_KEY=" + $key] + ($script | split("\n")))}' \
    > deploy-params.json

  CMD_ID=$(aws ssm send-command --region us-east-1 \
    --instance-ids i-02493c4d817d45bf4 \
    --document-name AWS-RunShellScript \
    --parameters file://deploy-params.json \
    --output text --query 'Command.CommandId')

  aws ssm get-command-invocation --region us-east-1 \
    --command-id "$CMD_ID" --instance-id i-02493c4d817d45bf4 \
    --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'

  rm -f deploy-params.json
  cd ..
}

deploy_service demo-app-db
deploy_service demo-app
deploy_service demo-orchestrator
```

## Break / fix the app (the actual demo switch)

No SSM/redeploy needed - `?break=true` propagates orchestrator -> app -> db,
so just change the URL against the orchestrator's public port:
```
curl "http://$IP:8080/api/orders?break=true"    # break it (fails at the DB tier)
curl "http://$IP:8080/api/orders"                # fix it (default is healthy)
```

## Test / verify the service

```
IP=$(aws ec2 describe-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

curl "http://$IP:8080/"
curl "http://$IP:8080/health"
curl "http://$IP:8080/api/orders"
```

EC2 status checks (stand in for "is infra healthy" - takes a couple of
minutes to settle after the instance starts):
```
aws ec2 describe-instance-status --region us-east-1 --instance-ids i-02493c4d817d45bf4 \
  --query 'InstanceStatuses[0].{Instance:InstanceStatus.Status,System:SystemStatus.Status}'
```

CloudWatch logs, one log group per tier (after breaking the app, only
`demo-app-db`'s should show ERROR lines):
```
for GROUP in demo-orchestrator demo-app demo-app-db; do
  echo "--- $GROUP ---"
  MSYS_NO_PATHCONV=1 aws logs filter-log-events --region us-east-1 \
    --log-group-name "/aws/ec2/$GROUP" --filter-pattern "ERROR" \
    --query 'events[].message'
done
```
(`MSYS_NO_PATHCONV=1` is only needed on Windows/git-bash, which otherwise
mangles the leading `/` in the log group name.)

## Metrics and alarms

Each tier's `ERROR` log line is turned into a CloudWatch metric
(`PocAwsDemo` namespace: `OrchestratorErrorCount`, `AppErrorCount`,
`DbErrorCount`) via a log metric filter - no code change needed. Check the
counts after breaking the app (expect `DbErrorCount` > 0, the other two 0):
```
for METRIC in OrchestratorErrorCount AppErrorCount DbErrorCount; do
  echo "--- $METRIC ---"
  aws cloudwatch get-metric-statistics --region us-east-1 \
    --namespace PocAwsDemo --metric-name "$METRIC" \
    --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 --statistics Sum --query 'Datapoints[].Sum'
done
```

An alarm (`pocaws-db-errors`) fires when `DbErrorCount` > 0 for one 60s
period - it flips to ALARM state within ~1-2 minutes of breaking the app:
```
aws cloudwatch describe-alarms --region us-east-1 --alarm-names pocaws-db-errors \
  --query 'MetricAlarms[0].StateValue'
```

## X-Ray traces

The X-Ray daemon runs once on the instance and receives segments from all
three services. After hitting `/api/orders` a few times (broken and/or
healthy), view the service map/traces in the Console (X-Ray -> Traces, or
Service map) showing `demo-orchestrator -> demo-app -> demo-app-db` as
three nodes, with the DB node red on a broken request. Or via CLI:
```
aws xray get-trace-summaries --region us-east-1 \
  --start-time "$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s)" \
  --end-time "$(date -u +%s)" \
  --query 'TraceSummaries[].{Id:Id,Duration:Duration,HasError:HasError}'
```
Fetch one trace's full detail (segment-by-segment) with `aws xray
batch-get-traces --trace-ids <id>`.

## Bonus scenario: CloudTrail (config drift, not an app bug)

A different failure mode for the talk: nothing about the app is broken,
but "a teammate changed something." `demo-common/cloudtrail-scenario.sh`
makes a harmless, reversible EC2 tag change as a stand-in for a real
config change (e.g. an edited security group rule), then shows how to find
who/what/when in CloudTrail:

```
bash demo-common/cloudtrail-scenario.sh i-02493c4d817d45bf4
```

Run this a few minutes before you need it in the talk (CloudTrail can take
up to ~15 min to surface a new event in `lookup-events`). Then live:
```
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=i-02493c4d817d45bf4 \
  --max-results 5
```
