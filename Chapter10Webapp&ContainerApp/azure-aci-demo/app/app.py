import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template

app = Flask(__name__)

APP_TITLE = os.getenv("APP_TITLE", "Hello from Azure Container Instances")
APP_ENV = os.getenv("APP_ENV", "demo")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")


@app.route("/")
def index():
    return render_template(
        "index.html",
        title=APP_TITLE,
        env=APP_ENV,
        version=APP_VERSION,
        hostname=socket.gethostname(),
        time=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
    )


@app.route("/health")
def health():
    return jsonify(status="healthy", version=APP_VERSION), 200


@app.route("/api/info")
def info():
    return jsonify(
        title=APP_TITLE,
        environment=APP_ENV,
        version=APP_VERSION,
        hostname=socket.gethostname(),
        utc_time=datetime.now(timezone.utc).isoformat(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "80")))
