#!/usr/bin/env python3
"""
Generates healthy + broken requests against the orchestrator's public
/api/orders endpoint, IN PARALLEL, so CloudWatch Logs/Metrics and X-Ray
already have real data before you open the console during the talk.

Stdlib only - nothing to pip install. Run a few minutes before you need
to show the console (CloudWatch/X-Ray ingestion takes a short moment).

Usage:
    python3 generate-traffic.py [ip] [--healthy N] [--broken N] [--concurrency N]

If ip is omitted, it's looked up via the AWS CLI (aws must be on PATH and
configured). Defaults: 1000 healthy, 30 broken, concurrency 20.
"""
import argparse
import os
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

REGION = "us-east-1"


def get_instance_ip():
    # Instance ID isn't hardcoded - the instance is fully Terraform-managed
    # now and gets replaced occasionally (e.g. AMI changes), so always ask
    # Terraform for the current one instead of a stale literal.
    infra_dir = os.path.join(os.path.dirname(__file__), "..", "infra")
    result = subprocess.run(
        ["terraform", f"-chdir={infra_dir}", "output", "-raw", "instance_public_ip"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def call(url, timeout=5):
    """Returns the HTTP status code, or None if the request failed/timed out."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code  # e.g. 500 - still a real response, not a failure
    except Exception:
        return None


def run_batch(label, url, count, concurrency):
    print(f"\n--- {count} {label} requests (concurrency={concurrency}) ---")
    counts = {}
    done = 0
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(call, url) for _ in range(count)]
        for future in as_completed(futures):
            code = future.result()
            counts[code] = counts.get(code, 0) + 1
            done += 1
            if done % 100 == 0 or done == count:
                print(f"  [{done}/{count}] {counts}")
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ip", nargs="?", default=None)
    parser.add_argument("--healthy", type=int, default=1000)
    parser.add_argument("--broken", type=int, default=30)
    parser.add_argument("--concurrency", type=int, default=20)
    args = parser.parse_args()

    ip = args.ip or get_instance_ip()
    if not ip or ip == "None":
        sys.exit("Could not determine the instance's public IP - is it running?")

    base_url = f"http://{ip}:8080"
    print(f"Target: {base_url}")

    run_batch("healthy", f"{base_url}/api/orders", args.healthy, args.concurrency)
    run_batch("broken (?break=true)", f"{base_url}/api/orders?break=true", args.broken, args.concurrency)

    print("\n--- 1 final healthy request (so the baseline tab you'll show first is fixed) ---")
    print(f"  GET /api/orders -> {call(f'{base_url}/api/orders')}")

    print("\nDone. Give CloudWatch Logs/Metrics and X-Ray a minute to ingest, then check:")
    print(f"  - Logs:    aws logs filter-log-events --region {REGION} --log-group-name /aws/ec2/demo-app-db --filter-pattern ERROR")
    print("  - Metrics: CloudWatch -> Metrics -> PocAwsDemo -> DbErrorCount")
    print(f"  - Alarm:   aws cloudwatch describe-alarms --region {REGION} --alarm-names pocaws-db-errors --query 'MetricAlarms[0].StateValue'")
    print("  - Traces:  X-Ray -> Traces / Service map (look for the demo-app-db node in red)")


if __name__ == "__main__":
    main()
