import os
import sqlite3
import sys

from aws_xray_sdk.core import patch_all, xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
from flask import Flask, jsonify, request

# sampling=False: trace every request, not just the default 1/sec + 5% -
# fine for low demo volume, NOT how you'd run this in production.
xray_recorder.configure(service="demo-app-db", sampling=False)
patch_all()    # instruments the requests library so the call below traces

app = Flask(__name__)
XRayMiddleware(app, xray_recorder) # register hooks for receiving a request (checks if it has a traceId, if not generate a new one)

DB_PATH = os.environ.get("DB_PATH", "/opt/pocaws-demo-db/orders.db")


@app.before_request
def log_request():
    trace_id = xray_recorder.current_segment().trace_id
    print(f"INFO: {request.method} {request.path} trace_id={trace_id}")


def query_orders():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY)")
    conn.execute("INSERT OR IGNORE INTO orders (id) VALUES (42)")
    conn.commit()
    count = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    conn.close()
    return count


@app.route("/")
def home():
    return jsonify(status="ok"), 200


@app.route("/health")
def health():
    # Always 200 - the health check has no idea the DB call is about to fail.
    return jsonify(status="healthy"), 200


@app.route("/api/orders")
def orders():
    # Pass ?break=true to simulate the DB failure live, no redeploy/restart needed.
    if request.args.get("break", "false").lower() == "true":
        trace_id = xray_recorder.current_segment().trace_id
        print(f"ERROR: Simulated database failure - Connection Timeout trace_id={trace_id}", file=sys.stderr)
        return jsonify(error="Internal Server Error"), 500

    count = query_orders()
    return jsonify(status="ok", orders=count), 200


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8082, threaded=True)
