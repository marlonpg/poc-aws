# Running this project

Operational commands for the 3-tier lightning-talk demo and its Terraform
(`infra/`). All commands assume you're in the repo root unless a `cd` is
shown. Requires `aws` CLI, `terraform`, and `jq`.

AWS auth: the `default` CLI profile is `pocaws-admin` (a scoped IAM user,
not root) - no `--profile` flag needed on any command below.

**Instance ID changes whenever the instance is replaced** (it's fully
Terraform-managed now - see "First boot" below), so don't hardcode it.
Every command below assumes you've set:
```
INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)
```

## Architecture

```
client -> demo-orchestrator (:8080, public) -> demo-app (:8081, localhost) -> demo-app-db (:8082, localhost, sqlite)
```

All three run as separate systemd services on one EC2 instance (fully
Terraform-managed - `infra/ec2_instance.tf`), under the same `pocaws-demo`
system user. Only `demo-orchestrator` is reachable from outside (port
8080, security group scoped to your IP) - the other two bind `127.0.0.1`
and are unreachable regardless of security group rules. `?break=true` on
`demo-orchestrator`'s `/api/orders` propagates all the way down to
`demo-app-db`, where the actual simulated failure happens.

## First boot - fully automatic, nothing manual

`terraform apply` is the entire setup. The instance's `user_data` (built
from `demo-common/bootstrap-common.sh` + each service's `deploy.sh`,
concatenated - see `infra/ec2_instance.tf`) runs once at first boot and:
installs Python/pip packages, the CloudWatch agent (config pulled from an
`aws_ssm_parameter`, not a local file), the X-Ray daemon, then pulls each
service's `app.py` from S3 (uploaded by Terraform itself via
`aws_s3_object`) and starts all 3 systemd services. No SSH, no SSM command
needed to get from zero to a working demo.

**AMI gotcha that bit us once**: the AMI filter must resolve to the
*standard* Amazon Linux 2023 AMI (`al2023-ami-2023.*-x86_64`), not the
*minimal* variant (`al2023-ami-minimal-*`) - minimal doesn't ship the SSM
Agent, which silently breaks every SSM-based command below. Already fixed
in `infra/ec2_instance.tf`, documented here so nobody "fixes" the filter
back to something looser.

Takes ~1-2 minutes after `terraform apply` for the instance to be usable
(package installs + pip installs). Check progress:
```
INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)
aws ssm send-command --region us-east-1 --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters commands="cloud-init status" \
  --output text --query 'Command.CommandId'
# then: aws ssm get-command-invocation --command-id <id> --instance-id "$INSTANCE_ID" --query StandardOutputContent
```

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

## Apply/update the Terraform infra

```
cd infra
terraform plan    # review: unexpected destroys of aws_instance.app mean a
                   # replace is coming (e.g. user_data changed) - the new
                   # instance self-provisions again automatically either way
terraform apply
cd ..
```

## Start / stop the instance

The instance is stopped between sessions to save cost. Start it before
doing anything else - this does NOT re-run `user_data` (that only runs on
first boot of a given instance), the 3 services come back up on their own
since they're `systemd enable`d:

```
INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)

aws ec2 start-instances --region us-east-1 --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-running --region us-east-1 --instance-ids "$INSTANCE_ID"

# wait for SSM agent to register (usually <1 min):
aws ssm describe-instance-information --region us-east-1 \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus'
```

Get its current public IP (changes on every start/stop - or just
`terraform -chdir=infra output -raw instance_public_ip`):
```
aws ec2 describe-instances --region us-east-1 --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

When done:
```
aws ec2 stop-instances --region us-east-1 --instance-ids "$INSTANCE_ID"
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

## Redeploy a service after a code change

First boot handles itself (see above) - this is for *after* that, when
you've edited one of the 3 `app.py` files. `terraform apply` alone is
enough to get the new code onto S3 (the `aws_s3_object` resources detect
the content change), but the running instance won't pick it up by itself -
run the matching service's `deploy.sh` via SSM:

```
cd infra && terraform apply && cd ..   # uploads the changed app.py to S3

INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)
BUCKET=$(terraform -chdir=infra output -raw artifact_bucket_name)

deploy_service() {
  local service="$1"   # demo-app-db | demo-app | demo-orchestrator
  cd "$service"

  jq -n --rawfile script deploy.sh --arg bucket "$BUCKET" --arg key "$service/app.py" \
    '{commands: (["export S3_BUCKET=" + $bucket, "export S3_KEY=" + $key] + ($script | split("\n")))}' \
    > deploy-params.json

  CMD_ID=$(aws ssm send-command --region us-east-1 \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters file://deploy-params.json \
    --output text --query 'Command.CommandId')

  aws ssm get-command-invocation --region us-east-1 \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'

  rm -f deploy-params.json
  cd ..
}

deploy_service demo-app-db   # only the service(s) you actually changed
```

If you ever need to re-run the shared setup by hand (installing
packages/agents - normally only needed once, at first boot):
```
CMD_ID=$(aws ssm send-command --region us-east-1 \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters commands="$(cat demo-common/bootstrap-common.sh)" \
  --output text --query 'Command.CommandId')

aws ssm get-command-invocation --region us-east-1 \
  --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'
```

## Break / fix the app (the actual demo switch)

No SSM/redeploy needed - `?break=true` propagates orchestrator -> app -> db,
so just change the URL against the orchestrator's public port:
```
curl "http://$IP:8080/api/orders?break=true"    # break it (fails at the DB tier)
curl "http://$IP:8080/api/orders"                # fix it (default is healthy)
```

To pre-generate a realistic mix of healthy + broken requests - IN PARALLEL,
not sequential - so CloudWatch Logs/Metrics and X-Ray already have data
before you open the console during the talk (run a few minutes ahead of
time). Python stdlib only, nothing to pip install:
```
python3 demo-common/generate-traffic.py
# or: python3 demo-common/generate-traffic.py <ip> --healthy N --broken N --concurrency N
```

## Test / verify the service

```
INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)
IP=$(terraform -chdir=infra output -raw instance_public_ip)

curl "http://$IP:8080/"
curl "http://$IP:8080/health"
curl "http://$IP:8080/api/orders"
```

EC2 status checks (stand in for "is infra healthy" - takes a couple of
minutes to settle after the instance starts):
```
aws ec2 describe-instance-status --region us-east-1 --instance-ids "$INSTANCE_ID" \
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

The `pocaws-demo` dashboard (`terraform -chdir=infra output -raw
dashboard_url`) puts the error-count graph, the alarm, and a log table on
one screen.

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
INSTANCE_ID=$(terraform -chdir=infra output -raw instance_id)
bash demo-common/cloudtrail-scenario.sh "$INSTANCE_ID"
```

Run this a few minutes before you need it in the talk (CloudTrail can take
up to ~15 min to surface a new event in `lookup-events`). Then live:
```
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue="$INSTANCE_ID" \
  --max-results 5
```
