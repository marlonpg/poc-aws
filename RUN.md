# Running this project

Operational commands for the lightning-talk demo (`demo-app/`) and its
Terraform (`infra/`). All commands assume you're in the repo root unless a
`cd` is shown. Requires `aws` CLI, `terraform`, and `jq`.

AWS auth: the `default` CLI profile is `pocaws-admin` (a scoped IAM user,
not root) - no `--profile` flag needed on any command below.

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

The instance (`i-02493c4d817d45bf4`) is stopped between sessions to save
cost. Start it before doing anything else:

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

The security group only allows port 8080 from `admin_cidr` in
`infra/terraform.tfvars`. Check your current IP and update it if needed:

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

## Deploy / redeploy the demo app

Same command for first deploy and redeploys - `deploy.sh` is idempotent
(re-installs packages if missing, restarts the service either way). Use
this any time you change `demo-app/app.py`:

```
cd demo-app
BUCKET=$(terraform -chdir=../infra output -raw artifact_bucket_name)

aws s3 cp app.py "s3://$BUCKET/demo-app/app.py"

jq -n --rawfile script deploy.sh --arg bucket "$BUCKET" --arg key "demo-app/app.py" \
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
```

## Break / fix the app (the actual demo switch)

No SSM/redeploy needed - `/api/orders` breaks based on a query param, so
just change the URL:
```
curl "http://$IP:8080/api/orders?break=true"    # break it
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

CloudWatch logs (after breaking the app):
```
MSYS_NO_PATHCONV=1 aws logs filter-log-events --region us-east-1 \
  --log-group-name "/aws/ec2/demo-app" --filter-pattern "ERROR" \
  --query 'events[].message'
```
(`MSYS_NO_PATHCONV=1` is only needed on Windows/git-bash, which otherwise
mangles the leading `/` in the log group name.)
