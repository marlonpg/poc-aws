# Lightning talk demo app

A tiny Flask API used for the "infra healthy, app broken" demo in
`../NEW-PRESENTATION.md`. Runs directly on the existing EC2 instance -
no ALB, no new IAM setup. Uses the same AWS CLI auth and instance role
already set up in `../infra`.

Endpoints: `/` and `/health` always return 200. `/api/orders` returns 500
when called with `?break=true` - just a query param, no restart or
redeploy needed, so it's safe to flip live during the talk from the
browser address bar or curl.

AWS CLI auth: the `default` profile now points at the scoped `pocaws-admin`
IAM user (not root) - plain `aws` commands below need no `--profile` flag.
`jq` is required for the one-time deploy step (used to build a valid SSM
command payload - see note below).

**Note on SSM parameters**: `AWS-RunShellScript` only accepts a `commands`
array - there's no way to pass arbitrary `KEY=value` parameters straight on
the CLI. The deploy command below builds a small JSON params file with `jq`
that bakes the value in as an `export` line at the top of the script.

## One-time setup

0. Start the instance if it's stopped, and wait for SSM to see it:
   ```
   aws ec2 start-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4
   aws ec2 wait instance-running --region us-east-1 --instance-ids i-02493c4d817d45bf4
   aws ssm describe-instance-information --region us-east-1 \
     --filters "Key=InstanceIds,Values=i-02493c4d817d45bf4" \
     --query 'InstanceInformationList[0].PingStatus'
   # repeat until this prints "Online" (usually <1 min after running)
   ```

1. Apply the Terraform additions (CloudWatch log group + agent permission
   on the existing instance role):
   ```
   cd ../infra
   terraform apply
   ```

2. Upload the app to the existing artifact bucket:
   ```
   cd ../demo-app
   BUCKET=$(terraform -chdir=../infra output -raw artifact_bucket_name)
   aws s3 cp app.py "s3://$BUCKET/demo-app/app.py"
   ```

3. Install and start it on the instance via SSM:
   ```
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
     --query '{Status:Status,Output:StandardOutputContent}'
   ```
   (Windows/git-bash: pass the log group name in CloudWatch commands with
   `MSYS_NO_PATHCONV=1` prefixed, or git-bash will mangle the leading `/`.)

4. Confirm it's reachable (security group already allows your IP on 8080,
   see `../infra/terraform.tfvars` - check `curl https://checkip.amazonaws.com`
   still matches `admin_cidr` there, IPs change):
   ```
   IP=$(terraform -chdir=../infra output -raw instance_public_ip)
   curl "http://$IP:8080/api/orders"
   ```

## During the talk

- **Baseline**: browser tab open on `http://<instance_public_ip>:8080/api/orders`.
- **Break it**: change the URL to `http://<instance_public_ip>:8080/api/orders?break=true`
  and refresh (or `curl "http://<instance_public_ip>:8080/api/orders?break=true"`) -
  instant 500, no SSM round-trip.
- **"Is infra healthy?"**: EC2 console -> Instances -> select the instance ->
  Status Checks tab. Both checks pass. (No ALB/Target Group in this version -
  the point is the same: the instance layer has no idea the app is broken.)
  Status checks take a couple of minutes to settle right after the instance
  starts, so do step 0 well before the talk, not seconds before.
- **Logs**: CloudWatch -> Log groups -> `/aws/ec2/demo-app` -> Logs Insights,
  same query as in the presentation doc.
- **Fix it**: drop `?break=true` from the URL (or just use `/api/orders`).

## Teardown

The instance and its role/SG stick around (they predate this demo). Nothing
here needs destroying - run the "Fix it" step to leave it healthy, then:
```
aws ec2 stop-instances --region us-east-1 --instance-ids i-02493c4d817d45bf4
```
to stop paying for compute until the next run.
