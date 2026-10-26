import os
import sys

import requests
from aws_xray_sdk.core import patch_all, xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
from flask import Flask, jsonify, request

# sampling=False: trace every request, not just the default 1/sec + 5% -
# fine for low demo volume, NOT how you'd run this in production.
xray_recorder.configure(service="demo-app", sampling=False)
patch_all()  # instruments the requests library so the call below traces (when calling a get/sqllite...)

app = Flask(__name__)
XRayMiddleware(app, xray_recorder) # register hooks for receiving a request (checks if it has a traceId, if not generate a new one)

DB_SERVICE_URL = os.environ.get("DB_SERVICE_URL", "http://127.0.0.1:8082")


@app.before_request
def log_request():
    trace_id = xray_recorder.current_segment().trace_id
    print(f"INFO: {request.method} {request.path} trace_id={trace_id}")


@app.route("/")
def home():
    return jsonify(status="ok"), 200


@app.route("/health")
def health():
    # Always 200 - doesn't check the downstream DB service at all.
    return jsonify(status="healthy"), 200


@app.route("/api/orders")
def orders():
    break_param = request.args.get("break", "false")
    try:
        resp = requests.get(f"{DB_SERVICE_URL}/api/orders", params={"break": break_param}, timeout=5)
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        trace_id = xray_recorder.current_segment().trace_id
        print(f"ERROR: demo-app-db unreachable - {exc} trace_id={trace_id}", file=sys.stderr)
        return jsonify(error="Internal Server Error"), 500


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081, threaded=True)
