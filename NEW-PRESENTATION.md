# AWS Troubleshooting

## 1. Intro

*"This is a POC I built: three small services -
`demo-orchestrator` (public, port 8080) calls `demo-app` (port 8081),
which calls `demo-app-db` (port 8082, a real sqlite connection) -
all running on one EC2 instance. Everything's provisioned with Terraform:
`infra/` has the security group, the instance's IAM role, CloudWatch log
groups, the metric/alarm setup, and the dashboard - about a dozen small
.tf files, no manual console clicking to set any of it up."*


## 2. AWS-native troubleshooting tools

- **AWS Health Dashboard** - is it AWS's fault?
- **EC2 Status Checks** - is the instance itself healthy?
- **CloudWatch** - logs, metrics, alarms, dashboards
- **X-Ray** - distributed tracing across services
- **CloudTrail** - audit log of who did what to your AWS account


## 3. Generate traffic

`demo-common/generate-traffic.py` - stdlib only (no pip install), uses
`ThreadPoolExecutor` to fire requests concurrently instead of one at a
time, closer to real traffic than a sequential loop:

```
python3 demo-common/generate-traffic.py
# defaults: 1000 healthy + 30 broken requests, concurrency 20
```

Note for whoever re-runs this: the three Flask apps run with
`threaded=True` specifically so they can handle concurrent connections -
without it, parallel requests queue up behind each other and the error
rate goes up for the wrong reason (the test tool, not the scenario).

Run this a few minutes before showing the console - gives CloudWatch and
X-Ray a moment to ingest everything.

## 4. Classic troubleshooting steps - CloudWatch

From there, CloudWatch gives you more than just "search the logs":

- **Metric Filters** - turn a log line (e.g. `ERROR: ...`) into a number over time, with zero code change. That's how `DbErrorCount` exists in this project.
- **Alarms** - watch that metric and flip state automatically (`pocaws-db-errors`, defined in `infra/metrics.tf`).
- **Dashboards** - put graphs, an alarm widget, and a log table on one screen (`pocaws-demo` dashboard, `infra/dashboard.tf`) - instead of accessing 3 separate pages.
- **Logs Insights + Live Tail** - Logs Insights for ad-hoc queries (`fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc`); Live Tail for watching log lines appear in real time.
- **Container Insights**: not on by default, has to be enabled (an EKS add-on). Once it is, it automatically collects - no code change - CPU/memory/network at cluster, node, pod, and container level, pod restart counts, and comes with pre-built dashboards per cluster/namespace/pod. The newer "CloudWatch Observability" add-on also ships pod logs to CloudWatch automatically.


## 5. X-Ray and CloudTrail - what each one actually is

Two tools that get confused for each other. Define both clearly before
showing anything:

**X-Ray - what it is**: distributed tracing. It follows one request as it
crosses multiple services, timing every hop.
**What it's for**: answering "where in the chain did this request fail or
get slow?" - without it, you're guessing which of N services to even look
at.
**Demo**: X-Ray -> Traces or Service map. Show `demo-orchestrator ->
demo-app -> demo-app-db` as three nodes, the DB node red on a broken
request. *"This is the real call graph, generated from actual traffic -
not a diagram someone drew and never updated."*

**CloudTrail - what it is**: an audit log of every API call made against
your AWS account - who, from where, when, with what parameters.
**What it's for**: answering "did a person or process change something,"
not "why did my code throw an error." It's not about your application at
all - it's about the AWS account itself.
**Demo**: run `demo-common/cloudtrail-scenario.sh "$(terraform -chdir=infra output -raw instance_id)"` a
few minutes ahead, then CloudTrail -> Event history -> filter by Resource
name = the instance ID -> open the `CreateTags` event -> point at
`userIdentity.arn` (who), `eventTime` (when), `requestParameters` (what).
