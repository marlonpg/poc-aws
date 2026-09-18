# AWS Troubleshooting Lightning Talk: Hands-On Guide

This document provides a deep dive into preparing your demo environment and executing the live presentation. It focuses on the "Option B" scenario (Infrastructure healthy, App broken) as it provides the best learning experience.

## Part 1: Preparing the Environment (Pre-Talk Setup)

To make this demo impactful, we want a small, predictable environment: `Internet -> EC2 -> Flask App -> CloudWatch`.
(No ALB in this version - see `demo-app/README.md` for why: for a short lightning-talk demo it isn't worth the extra setup, so we hit the instance directly and use EC2 Status Checks instead of Target Group health as the "infra looks fine" evidence.)

### 1. EC2 & IAM Setup (The Compute Layer)
Already done - this reuses the existing instance and IAM role in `../infra`:
*   **IAM Role**: `AmazonSSMManagedInstanceCore` (Session Manager access, no SSH keys/port 22 needed) and `CloudWatchAgentServerPolicy` (push logs to CloudWatch) are both attached to the instance role.
*   **Instance**: the existing Amazon Linux 2023 instance (`i-02493c4d817d45bf4`).
*   **Security Group**: inbound on port 8080 from your own IP only (`admin_cidr` in `infra/terraform.tfvars`).

### 2. Application Setup (The Victim)
The demo app lives in `demo-app/app.py` - a small Flask app with three
endpoints: `/` and `/health` always return 200, `/api/orders` returns 500
when called with `?break=true` (a query param, not an env var - flips
instantly with no restart, see Step 2 below). See `demo-app/README.md` for
how to deploy and run it.

*Setup Tip*: Runs as a `systemd` service (`demo-app/deploy.sh` sets this up) so it survives reboots and its output is captured to a log file.

### 3. CloudWatch Setup
`demo-app/deploy.sh` installs and configures the CloudWatch agent to stream
the app's log file to a Log Group named `/aws/ec2/demo-app` (created by
Terraform in `infra/cloudwatch.tf`).

---

## Part 2: Live Demo Execution (Steps to Show Your Team)

The core lesson for the team is: **A healthy infrastructure component does not necessarily mean a healthy application.** 

### Step 1: Establish the Baseline (0:00 - 1:00)
1.  **Console Page**: Open **EC2 -> Instances**, select the instance, copy its Public IPv4 address (or run `terraform output -raw instance_public_ip` in `infra/`).
2.  **Action**: Open a new browser tab and navigate to `http://<instance-ip>:8080/api/orders`.
3.  **Talking Point**: "Here is our application. Everything is working perfectly. The users are happy, orders are processing." (Show the JSON `{"status": "ok", "orders": 42}`).

### Step 2: Inject the Failure (1:00 - 2:00)
1.  **Action**: Change the browser tab's URL to `http://<instance-ip>:8080/api/orders?break=true` and refresh. It now shows a `500 Internal Server Error` - instant, no SSM/restart needed.
2.  **Talking Point**: "We have an incident. The hardest part is knowing where to start. We are going to work outside-in: AWS, Infrastructure, Application."

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

3.  **What do the logs say?**
    *   **Console Page**: Navigate to **CloudWatch -> Logs Insights**.
    *   **Action**: Select your Log Group (`/aws/ec2/demo-app`).
    *   **Action**: Run the following query:
        ```sql
        fields @timestamp, @message
        | filter @message like /ERROR/
        | sort @timestamp desc
        | limit 20
        ```
    *   **Action**: Expand the log line that says `ERROR: Simulated database failure - Connection Timeout`.
    *   **Talking Point**: "Instead of grepping through thousands of lines on the server, we centralize and query. We've instantly found the root cause: the app can't talk to the database."

### Step 4: Fix and Conclude (4:00 - 5:00)
1.  **Action**: Drop `?break=true` from the URL and refresh. The app is working again.
2.  **Closing Statement**: "Don't start by guessing the fix. Start by collecting evidence from the Load Balancer, to the Metrics, to the Logs."