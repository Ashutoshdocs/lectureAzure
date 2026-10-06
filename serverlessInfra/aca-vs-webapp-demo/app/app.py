"""
Demo app: the SAME container image runs on Azure Web App (App Service)
and Azure Container Apps. Every response tells you WHERE it is running,
WHICH instance/replica answered, WHICH version it is, and WHEN that
instance started, so the platform differences become visible.
"""
import os
import socket
import threading
import time
from datetime import datetime, timezone

from flask import Flask, jsonify, request

app = Flask(__name__)

STARTED_AT = datetime.now(timezone.utc)
APP_VERSION = os.getenv("APP_VERSION", "v1")
_lock = threading.Lock()
_request_count = 0


def detect_platform():
    """Each platform injects its own environment variables."""
    if os.getenv("CONTAINER_APP_NAME"):
        return "Azure Container Apps"
    if os.getenv("WEBSITE_SITE_NAME"):
        return "Azure Web App (App Service)"
    return "Local / Docker"


def instance_id():
    """Identity of the instance/replica that served this request."""
    return (
        os.getenv("CONTAINER_APP_REPLICA_NAME")        # Container Apps replica
        or os.getenv("WEBSITE_INSTANCE_ID", "")[:12]    # App Service instance
        or socket.gethostname()
    )


def count_request():
    global _request_count
    with _lock:
        _request_count += 1
        return _request_count


def info_payload():
    now = datetime.now(timezone.utc)
    return {
        "platform": detect_platform(),
        "version": APP_VERSION,
        "instance": instance_id(),
        "hostname": socket.gethostname(),
        "instance_started_at": STARTED_AT.isoformat(),
        "instance_uptime_seconds": round((now - STARTED_AT).total_seconds(), 1),
        "requests_served_by_this_instance": count_request(),
        "platform_env": {
            # Container Apps variables
            "CONTAINER_APP_NAME": os.getenv("CONTAINER_APP_NAME"),
            "CONTAINER_APP_REVISION": os.getenv("CONTAINER_APP_REVISION"),
            "CONTAINER_APP_REPLICA_NAME": os.getenv("CONTAINER_APP_REPLICA_NAME"),
            "CONTAINER_APP_ENV_DNS_SUFFIX": os.getenv("CONTAINER_APP_ENV_DNS_SUFFIX"),
            # App Service variables
            "WEBSITE_SITE_NAME": os.getenv("WEBSITE_SITE_NAME"),
            "WEBSITE_SKU": os.getenv("WEBSITE_SKU"),
            "WEBSITE_INSTANCE_ID": os.getenv("WEBSITE_INSTANCE_ID"),
            "WEBSITE_HOSTNAME": os.getenv("WEBSITE_HOSTNAME"),
        },
    }


@app.route("/api/info")
def api_info():
    return jsonify(info_payload())


@app.route("/health")
def health():
    return jsonify(status="healthy", version=APP_VERSION)


@app.route("/work")
def work():
    """Simulates a slow request (default 500 ms) so load builds up concurrency."""
    ms = min(int(request.args.get("ms", 500)), 5000)
    time.sleep(ms / 1000)
    return jsonify(version=APP_VERSION, instance=instance_id(), slept_ms=ms)


@app.route("/")
def index():
    d = info_payload()
    color = "#2563eb" if APP_VERSION == "v1" else "#16a34a"
    rows = "".join(
        f"<tr><td>{k}</td><td>{v if v else '<span class=muted>not set</span>'}</td></tr>"
        for k, v in d["platform_env"].items()
    )
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{d['platform']} demo</title>
<style>
 body{{font-family:system-ui,Segoe UI,Arial;margin:0;background:#f4f6fa;color:#1f2937}}
 header{{background:{color};color:#fff;padding:24px 32px}}
 h1{{margin:0;font-size:26px}} main{{padding:24px 32px;max-width:900px}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}}
 .card{{background:#fff;border-radius:10px;padding:14px 16px;box-shadow:0 1px 3px #0001}}
 .card b{{display:block;font-size:12px;color:#6b7280;text-transform:uppercase}}
 .card span{{font-size:18px;word-break:break-all}}
 table{{width:100%;background:#fff;border-collapse:collapse;margin-top:20px;border-radius:10px;overflow:hidden}}
 td{{padding:8px 12px;border-bottom:1px solid #eee;font-family:monospace;font-size:13px}}
 .muted{{color:#9ca3af}}
</style></head>
<body>
<header><h1>Running on: {d['platform']}</h1><div>Image version <b>{d['version']}</b> &middot; refresh to see which instance answers</div></header>
<main>
 <div class="grid">
  <div class="card"><b>Instance / replica</b><span>{d['instance']}</span></div>
  <div class="card"><b>Instance started (UTC)</b><span>{d['instance_started_at'][:19]}</span></div>
  <div class="card"><b>Uptime (s)</b><span>{d['instance_uptime_seconds']}</span></div>
  <div class="card"><b>Requests on this instance</b><span>{d['requests_served_by_this_instance']}</span></div>
 </div>
 <h3>Platform-injected environment variables</h3>
 <table>{rows}</table>
 <p class="muted">Endpoints: /api/info &middot; /health &middot; /work?ms=500</p>
</main></body></html>"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8000)))
