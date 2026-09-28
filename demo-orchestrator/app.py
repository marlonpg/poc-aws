import os
import sys

import requests
from aws_xray_sdk.core import patch_all, xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
from flask import Flask, jsonify, request

xray_recorder.configure(service="demo-orchestrator")
patch_all()  # instruments the requests library so the call below traces

app = Flask(__name__)
XRayMiddleware(app, xray_recorder)

APP_SERVICE_URL = os.environ.get("APP_SERVICE_URL", "http://127.0.0.1:8081")


@app.route("/")
def home():
    return jsonify(status="ok"), 200


@app.route("/health")
def health():
    # Always 200 - doesn't check anything downstream.
    return jsonify(status="healthy"), 200


@app.route("/api/orders")
def orders():
    break_param = request.args.get("break", "false")
    try:
        resp = requests.get(f"{APP_SERVICE_URL}/api/orders", params={"break": break_param}, timeout=5)
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        print(f"ERROR: demo-app unreachable - {exc}", file=sys.stderr)
        return jsonify(error="Internal Server Error"), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
