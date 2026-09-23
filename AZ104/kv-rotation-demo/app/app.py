"""Key Vault rotation demo app.

Reads a secret from Azure Key Vault using the VM's managed identity and keeps it
in memory. Syncs automatically when the secret is rotated:
  * push: Event Grid (SecretNewVersionCreated) -> Storage Queue -> reload
  * pull: polls Key Vault every POLL_SECONDS as a safety net
"""
import base64
import json
import logging
import os
import threading
import time
from datetime import datetime, timezone

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.queue import QueueClient
from flask import Flask, jsonify

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("kvdemo")

KEYVAULT_URL = os.environ["KEYVAULT_URL"]               # https://<kv>.vault.azure.net
SECRET_NAME = os.environ.get("SECRET_NAME", "app-api-key")
QUEUE_ACCOUNT_URL = os.environ.get("QUEUE_ACCOUNT_URL")  # https://<st>.queue.core.windows.net
QUEUE_NAME = os.environ.get("QUEUE_NAME", "kv-events")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "60"))

credential = DefaultAzureCredential()  # resolves to the VM's managed identity
kv = SecretClient(vault_url=KEYVAULT_URL, credential=credential)

lock = threading.Lock()
state = {"value": None, "version": None, "loaded_at": None, "history": []}


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def load_secret(reason: str):
    s = kv.get_secret(SECRET_NAME)  # always returns the latest version
    with lock:
        if s.properties.version != state["version"]:
            state.update(value=s.value, version=s.properties.version, loaded_at=now())
            state["history"].insert(0, {"version": s.properties.version, "at": now(), "reason": reason})
            log.info("Secret loaded: version=%s reason=%s", s.properties.version, reason)
        else:
            log.info("Checked (%s): no change, version=%s", reason, s.properties.version)


def mask(v):
    return (v[:4] + "*" * 12) if v else None


# ---- Pull: poll Key Vault as a safety net ----
def poll_loop():
    while True:
        time.sleep(POLL_SECONDS)
        try:
            load_secret("poll")
        except Exception:
            log.exception("poll failed")


# ---- Push: Event Grid -> Storage Queue -> reload ----
def parse(msg_content: str) -> dict:
    try:
        return json.loads(msg_content)
    except json.JSONDecodeError:
        return json.loads(base64.b64decode(msg_content))


def queue_loop():
    qc = QueueClient(account_url=QUEUE_ACCOUNT_URL, queue_name=QUEUE_NAME, credential=credential)
    log.info("Listening for rotation events on queue '%s'", QUEUE_NAME)
    while True:
        try:
            for msg in qc.receive_messages(messages_per_page=10, visibility_timeout=30):
                evt = parse(msg.content)
                etype = evt.get("eventType", "")
                subject = evt.get("subject", "")
                log.info("Event received: %s subject=%s", etype, subject)
                if etype.endswith("SecretNewVersionCreated") and subject == SECRET_NAME:
                    load_secret("event-grid")
                qc.delete_message(msg)
        except Exception:
            log.exception("queue listener error")
        time.sleep(5)


app = Flask(__name__)


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/api/secret")
def api_secret():
    with lock:
        return jsonify(name=SECRET_NAME, version=state["version"], masked_value=mask(state["value"]),
                       loaded_at=state["loaded_at"], history=state["history"][:10])


@app.post("/api/refresh")
def api_refresh():
    load_secret("manual-refresh")
    return api_secret()


@app.get("/")
def index():
    with lock:
        rows = "".join(f"<tr><td><code>{h['version'][:12]}…</code></td><td>{h['at']}</td>"
                       f"<td>{h['reason']}</td></tr>" for h in state["history"][:10])
        return f"""<!doctype html><html><head><meta http-equiv="refresh" content="3">
<title>Key Vault Rotation Demo</title>
<style>body{{font-family:system-ui;max-width:720px;margin:40px auto;padding:0 16px}}
.card{{border:1px solid #ccc;border-radius:10px;padding:16px;margin-bottom:16px}}
td,th{{padding:4px 12px;text-align:left}}</style></head><body>
<h1>🔐 Key Vault Rotation Demo</h1>
<div class="card"><b>Secret:</b> {SECRET_NAME}<br>
<b>Current version:</b> <code>{state['version']}</code><br>
<b>Value (masked):</b> <code>{mask(state['value'])}</code><br>
<b>Loaded at:</b> {state['loaded_at']}</div>
<form method="post" action="/api/refresh"><button>Force refresh</button></form>
<h3>Version history (this app instance)</h3>
<table><tr><th>Version</th><th>Loaded</th><th>Trigger</th></tr>{rows}</table>
<p><small>Page auto-refreshes every 3 seconds. Poll interval: {POLL_SECONDS}s.</small></p>
</body></html>"""


# Start-up: load the secret once, then start the background sync threads
load_secret("startup")
threading.Thread(target=poll_loop, daemon=True).start()
if QUEUE_ACCOUNT_URL:
    threading.Thread(target=queue_loop, daemon=True).start()
