# AWS Troubleshooting Lightning Talk: Hands-On Guide

This document provides a deep dive into preparing your demo environment and executing the live presentation. It focuses on the "Option B" scenario (Infrastructure healthy, App broken) as it provides the best learning experience, then adds two bonus segments (metrics/alarms + X-Ray, and a CloudTrail config-drift scenario) if time allows.

## Part 1: Preparing the Environment (Pre-Talk Setup)

To make this demo impactful, we use a small, predictable, 3-tier setup: `Internet -> demo-orchestrator -> demo-app -> demo-app-db (sqlite)`, all running as separate processes on one EC2 instance.
(No ALB in this version - for a short lightning-talk demo it isn't worth the extra setup, so the orchestrator is hit directly and EC2 Status Checks stand in for Target Group health as the "infra looks fine" evidence.)

### 1. EC2 & IAM Setup (The Compute Layer)
Already done - this reuses the existing instance and IAM role in `../infra`:
*   **IAM Role**: `AmazonSSMManagedInstanceCore` (Session Manager, no SSH keys/port 22), `CloudWatchAgentServerPolicy` (push logs), and `AWSXRayDaemonWriteAccess` (send trace segments) are all attached to the instance role.
*   **Instance**: the existing Amazon Linux 2023 instance (`i-02493c4d817d45bf4`).
*   **Security Group**: inbound on port 8080 (the orchestrator only) from your own IP (`admin_cidr` in `infra/terraform.tfvars`). The other two services bind `127.0.0.1` and are unreachable from outside regardless.

### 2. Application Setup (The Victim(s))
Three small Flask services, one per tier - see `RUN.md` for the full deploy/verify commands:
*   **`demo-orchestrator/app.py`** (port 8080, public) - calls `demo-app`.
*   **`demo-app/app.py`** (port 8081, internal) - calls `demo-app-db`.
*   **`demo-app-db/app.py`** (port 8082, internal) - a real sqlite connection standing in for a production database.

`/` and `/health` on every tier always return 200. `/api/orders` on the orchestrator forwards a `?break=true` query param all the way down the chain - no env var, no restart, just a URL change - and `demo-app-db` is where the actual simulated failure happens (`ERROR: Simulated database failure - Connection Timeout`).

*Setup Tip*: Each tier runs as its own `systemd` service (each service's `deploy.sh` sets this up) so it survives reboots and its output is captured to its own log file.

### 3. Observability Setup
`demo-common/bootstrap-common.sh` (run once) sets up all of this for all three services:
*   **CloudWatch Logs**: one log group per tier - `/aws/ec2/demo-orchestrator`, `/aws/ec2/demo-app`, `/aws/ec2/demo-app-db` (created by Terraform in `infra/cloudwatch.tf`).
*   **CloudWatch Metrics + Alarm**: a log metric filter per tier turns each `ERROR` line into a metric (`PocAwsDemo` namespace), and an alarm watches the DB tier's metric (`infra/metrics.tf`).
*   **X-Ray**: one daemon on the instance receives trace segments from all three services, so a single request shows up as a 3-node distributed trace.

---

## Part 2: Live Demo Execution (Steps to Show Your Team)

The core lesson for the team is: **A healthy infrastructure component does not necessarily mean a healthy application - and in a multi-service system, the failure can be several hops away from what the user actually sees.**

### Step 1: Establish the Baseline (0:00 - 1:00)
1.  **Console Page**: Open **EC2 -> Instances**, select the instance, copy its Public IPv4 address (or run `terraform output -raw instance_public_ip` in `infra/`).
2.  **Action**: Open a new browser tab and navigate to `http://<instance-ip>:8080/api/orders`.
3.  **Talking Point**: "Here is our application - actually three services: an orchestrator, an app tier, and a DB tier. Everything is working perfectly. The users are happy, orders are processing." (Show the JSON `{"status": "ok", "orders": 42}`).

### Step 2: Inject the Failure (1:00 - 2:00)
1.  **Action**: Change the browser tab's URL to `http://<instance-ip>:8080/api/orders?break=true` and refresh. It now shows a `500 Internal Server Error` - instant, no SSM/restart needed. Under the hood this query param traveled orchestrator -> app -> db, and the DB tier is the one that actually failed.
2.  **Talking Point**: "We have an incident. The hardest part is knowing where to start - and now we don't even know which of our three services is at fault. We are going to work outside-in: AWS, Infrastructure, Application, then narrow down which service."

### Step 3: Investigate (2:00 - 4:00)
Follow the evidence trail exactly in this order:

1.  **Is AWS broken?**
    *   **Console Page**: Navigate to **AWS Health Dashboard**.
    *   **Action**: Briefly show there are no active AWS outages.
    *   **Talking Point**: "Sometimes we tear our apps apart when it's actually an AWS outage. Always check Health first."

2.  **Is the Infrastructure healthy?**
    *   **Console Page**: Navigate to **EC2 -> Instances**, select the instance, open the **Status Checks** tab.
    *   **Action**: Show both checks passing: **✅ 2/2 checks passed**.
    *   **Action** (optional, if you want the "still 200" beat): `curl http://<instance-ip>:8080/health`.
    *   **Talking Point**: "Look at this. The instance is completely healthy, and `/health` is still a 200 OK. Infrastructure health does NOT equal application health."

3.  **Which service is actually failing? (Metrics)**
    *   **Console Page**: Navigate to **CloudWatch -> Metrics -> All -> PocAwsDemo**.
    *   **Action**: Show `OrchestratorErrorCount` and `AppErrorCount` flat at zero, while `DbErrorCount` has a spike.
    *   **Talking Point**: "Before we even open a log, the metrics already tell us which of our three services is the culprit: the DB tier. In a system with more than one or two services, that's the difference between checking 10 log groups and checking one."
    *   **Bonus**: Show the `pocaws-db-errors` alarm flipping to ALARM state (CloudWatch -> Alarms).

4.  **What's the exact request path and where's the time going? (X-Ray)**
    *   **Console Page**: Navigate to **X-Ray -> Traces** (or **Service map**).
    *   **Action**: Open a recent trace for the broken request. Show the service map: `demo-orchestrator -> demo-app -> demo-app-db`, with the DB node marked in red/fault.
    *   **Talking Point**: "This is the actual call graph, not a diagram someone drew six months ago. We can see the request went through all three services and see exactly which segment failed - no guessing about which service called which."

5.  **What do the logs say? (root cause)**
    *   **Console Page**: Navigate to **CloudWatch -> Logs Insights**.
    *   **Action**: Select the `/aws/ec2/demo-app-db` log group (the one metrics + X-Ray already pointed to).
    *   **Action**: Run the following query:
        ```sql
        fields @timestamp, @message
        | filter @message like /ERROR/
        | sort @timestamp desc
        | limit 20
        ```
    *   **Action**: Expand the log line that says `ERROR: Simulated database failure - Connection Timeout`.
    *   **Talking Point**: "Metrics told us *which* service, X-Ray showed us *the path*, and the logs give us the *why*. Instead of grepping through three services' worth of logs, we went straight to the one that mattered."

### Step 4: Fix and Conclude (4:00 - 5:00)
1.  **Action**: Drop `?break=true` from the URL and refresh. The app is working again.
2.  **Closing Statement**: "Don't start by guessing the fix. Start by collecting evidence - from infrastructure health, to metrics, to traces, to logs - narrowing down at each step."

---

## Part 3 (Bonus): A Different Failure Mode - Config Drift via CloudTrail

Everything above is an *application* bug. Just as common in the real world: nothing about the code is broken, but **someone changed a setting** - a security group rule, an IAM policy, an instance attribute - and that's the incident. This is what CloudTrail is for: not "why did the app throw," but "who changed what, and when."

1.  **Setup** (do this a few minutes before you need it - CloudTrail can take up to ~15 min to surface a new event):
    ```
    bash demo-common/cloudtrail-scenario.sh i-02493c4d817d45bf4
    ```
    This makes a harmless, reversible EC2 tag change as a stand-in for a real config edit.
2.  **Console Page**: Navigate to **CloudTrail -> Event history**.
3.  **Action**: Filter by resource name = the instance ID (or run the `aws cloudtrail lookup-events` command from `RUN.md`).
4.  **Talking Point**: "This is the audit trail for *every* API call against your account - who, from where, and when. When the incident isn't a code bug but a change someone made, this is where you look first, before touching a single line of app code."

This trail (`pocaws-trail` in `infra/cloudtrail.tf`) has already been logging management events since before this demo existed, so this technique works retroactively too - you don't need to have planned for it in advance.
