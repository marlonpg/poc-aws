import os
import sqlite3
import sys

from aws_xray_sdk.core import patch_all, xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
from flask import Flask, jsonify, request

xray_recorder.configure(service="demo-app-db")
patch_all()  # instruments sqlite3 so its calls show up as X-Ray subsegments

app = Flask(__name__)
XRayMiddleware(app, xray_recorder)

DB_PATH = os.environ.get("DB_PATH", "/opt/pocaws-demo-db/orders.db")


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
        print("ERROR: Simulated database failure - Connection Timeout", file=sys.stderr)
        return jsonify(error="Internal Server Error"), 500

    count = query_orders()
    return jsonify(status="ok", orders=count), 200


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8082)
