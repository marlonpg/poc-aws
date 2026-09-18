import os
import sys

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route("/")
def home():
    return jsonify(status="ok"), 200


@app.route("/health")
def health():
    # Always 200 - this is the whole point of the demo: the health check
    # doesn't know the app is broken.
    return jsonify(status="healthy"), 200


@app.route("/api/orders")
def orders():
    # Pass ?break=true to simulate the failure live, no redeploy/restart needed.
    if request.args.get("break", "false").lower() == "true":
        print("ERROR: Simulated database failure - Connection Timeout", file=sys.stderr)
        return jsonify(error="Internal Server Error"), 500
    return jsonify(status="ok", orders=42), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
