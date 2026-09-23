"""
app.py — Two-Tier Architecture Demo (Web Tier)
================================================
Runs on:  vm-dev-eus-web-01  (10.0.0.4)  -- the "frontend" VM
Talks to: vm-dev-eus-db-01   (10.0.1.4)  -- the MySQL "database" VM

A small, self-contained Flask app that proves the two-tier NSG design works:
the web VM can reach MySQL on the private subnet, while the DB VM stays
locked away from the internet.

Environment variables (override the defaults if you like):
    DB_HOST      default 10.0.1.4      (private IP of vm-dev-eus-db-01)
    DB_PORT      default 3306
    DB_USER      default dbadmin
    DB_PASSWORD  default Microsoft2025
    DB_NAME      default appdb
    APP_PORT     default 80            (matches the "allow port 80" NSG rule)
"""

import os
from datetime import datetime

import pymysql
from flask import Flask, request, redirect, url_for, render_template_string

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "10.0.1.4"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "dbadmin"),
    "password": os.getenv("DB_PASSWORD", "Microsoft2025"),
    "database": os.getenv("DB_NAME", "appdb"),
    "cursorclass": pymysql.cursors.DictCursor,
    "connect_timeout": 5,
}
APP_PORT = int(os.getenv("APP_PORT", "80"))

app = Flask(__name__)


# ----------------------------------------------------------------------------
# Database helpers
# ----------------------------------------------------------------------------
def get_connection(with_db: bool = True):
    """Open a fresh connection. Set with_db=False for the very first bootstrap."""
    cfg = dict(DB_CONFIG)
    if not with_db:
        cfg.pop("database", None)
    return pymysql.connect(**cfg)


def init_db():
    """Create the database + table if they don't exist yet."""
    # Step 1: make sure the database exists (connect without selecting a DB)
    conn = get_connection(with_db=False)
    with conn.cursor() as cur:
        cur.execute(
            f"CREATE DATABASE IF NOT EXISTS {DB_CONFIG['database']} "
            "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
    conn.commit()
    conn.close()

    # Step 2: create the table inside that database
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id        INT AUTO_INCREMENT PRIMARY KEY,
                author    VARCHAR(80)  NOT NULL,
                body      VARCHAR(500) NOT NULL,
                created   DATETIME     NOT NULL
            )
            """
        )
    conn.commit()
    conn.close()


def db_status():
    """Return (ok, detail) describing the connection to the DB tier."""
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT VERSION() AS v")
            version = cur.fetchone()["v"]
        conn.close()
        return True, f"MySQL {version}"
    except Exception as exc:  # noqa: BLE001 - we want to surface any failure
        return False, str(exc)


# ----------------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------------
@app.route("/", methods=["GET"])
def index():
    ok, detail = db_status()
    messages = []
    if ok:
        try:
            conn = get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM messages ORDER BY created DESC LIMIT 50")
                messages = cur.fetchall()
            conn.close()
        except Exception as exc:  # noqa: BLE001
            ok, detail = False, str(exc)
    return render_template_string(
        PAGE,
        ok=ok,
        detail=detail,
        messages=messages,
        db_host=DB_CONFIG["host"],
    )


@app.route("/add", methods=["POST"])
def add():
    author = (request.form.get("author") or "Anonymous").strip()[:80]
    body = (request.form.get("body") or "").strip()[:500]
    if body:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO messages (author, body, created) VALUES (%s, %s, %s)",
                (author, body, datetime.utcnow()),
            )
        conn.commit()
        conn.close()
    return redirect(url_for("index"))


@app.route("/healthz", methods=["GET"])
def healthz():
    ok, detail = db_status()
    return ({"status": "up", "db": detail} if ok else {"status": "degraded", "db": detail}), (
        200 if ok else 503
    )


# ----------------------------------------------------------------------------
# UI  (single-file template — modern, responsive, no external assets)
# ----------------------------------------------------------------------------
PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Two-Tier Demo · Web Tier</title>
  <style>
    :root{
      --bg:#0b1020; --card:#141b30; --line:#243049;
      --text:#e8ecf6; --muted:#93a0bd; --brand:#5b8cff; --brand2:#7c5bff;
      --ok:#2fd07f; --bad:#ff5c72; --shadow:0 20px 60px rgba(0,0,0,.45);
    }
    *{box-sizing:border-box}
    body{
      margin:0; min-height:100vh; color:var(--text);
      font:16px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
      background:
        radial-gradient(1200px 600px at 80% -10%, rgba(124,91,255,.25), transparent 60%),
        radial-gradient(900px 500px at -10% 10%, rgba(91,140,255,.20), transparent 55%),
        var(--bg);
    }
    .wrap{max-width:860px; margin:0 auto; padding:48px 20px 80px}
    header{display:flex; align-items:center; gap:14px; margin-bottom:8px}
    .logo{
      width:46px;height:46px;border-radius:14px;flex:none;
      background:linear-gradient(135deg,var(--brand),var(--brand2));
      display:grid;place-items:center;font-weight:800;color:#fff;
      box-shadow:0 8px 24px rgba(91,140,255,.45);
    }
    h1{font-size:26px;margin:0;letter-spacing:.2px}
    .sub{color:var(--muted);margin:2px 0 0}
    .status{
      display:inline-flex;align-items:center;gap:10px;margin:22px 0 26px;
      padding:12px 16px;border-radius:14px;border:1px solid var(--line);
      background:linear-gradient(180deg,rgba(255,255,255,.03),rgba(255,255,255,0));
    }
    .dot{width:11px;height:11px;border-radius:50%}
    .dot.ok{background:var(--ok);box-shadow:0 0 0 5px rgba(47,208,127,.15)}
    .dot.bad{background:var(--bad);box-shadow:0 0 0 5px rgba(255,92,114,.15)}
    .status small{color:var(--muted)}
    .card{
      background:var(--card);border:1px solid var(--line);border-radius:20px;
      padding:24px;box-shadow:var(--shadow);
    }
    label{display:block;font-size:13px;color:var(--muted);margin:0 0 6px}
    input,textarea{
      width:100%;padding:12px 14px;border-radius:12px;border:1px solid var(--line);
      background:#0e1424;color:var(--text);font:inherit;outline:none;transition:.15s;
    }
    input:focus,textarea:focus{border-color:var(--brand);box-shadow:0 0 0 3px rgba(91,140,255,.25)}
    textarea{resize:vertical;min-height:84px}
    .row{display:grid;grid-template-columns:1fr;gap:14px}
    .actions{margin-top:16px;display:flex;justify-content:flex-end}
    button{
      border:0;cursor:pointer;color:#fff;font-weight:700;letter-spacing:.2px;
      padding:12px 22px;border-radius:12px;
      background:linear-gradient(135deg,var(--brand),var(--brand2));
      box-shadow:0 10px 24px rgba(124,91,255,.4);transition:transform .12s,filter .12s;
    }
    button:hover{transform:translateY(-1px);filter:brightness(1.06)}
    button:active{transform:translateY(0)}
    h2{font-size:15px;color:var(--muted);text-transform:uppercase;letter-spacing:1.2px;margin:34px 0 14px}
    .msg{
      border:1px solid var(--line);border-radius:16px;padding:14px 16px;margin-bottom:12px;
      background:linear-gradient(180deg,rgba(255,255,255,.02),rgba(255,255,255,0));
    }
    .msg .meta{display:flex;justify-content:space-between;gap:12px;color:var(--muted);font-size:13px;margin-bottom:6px}
    .msg .who{color:var(--brand);font-weight:700}
    .empty{color:var(--muted);text-align:center;padding:26px;border:1px dashed var(--line);border-radius:16px}
    .err{white-space:pre-wrap;color:#ffd7dd;background:rgba(255,92,114,.08);
         border:1px solid rgba(255,92,114,.3);border-radius:14px;padding:14px 16px;font-size:13px}
    footer{margin-top:34px;color:var(--muted);font-size:12.5px;text-align:center}
    code{background:#0e1424;border:1px solid var(--line);border-radius:6px;padding:1px 6px}
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="logo">2T</div>
      <div>
        <h1>Two-Tier Architecture Demo</h1>
        <p class="sub">Web tier · <code>vm-dev-eus-web-01</code> → DB tier · <code>{{ db_host }}</code></p>
      </div>
    </header>

    <div class="status">
      <span class="dot {{ 'ok' if ok else 'bad' }}"></span>
      {% if ok %}
        <div>Database connection <b>healthy</b> <small>· {{ detail }}</small></div>
      {% else %}
        <div>Database <b>unreachable</b> <small>· check the NSG rules</small></div>
      {% endif %}
    </div>

    {% if not ok %}
      <div class="err">{{ detail }}</div>
    {% endif %}

    <div class="card">
      <form method="post" action="/add">
        <div class="row">
          <div>
            <label for="author">Your name</label>
            <input id="author" name="author" placeholder="e.g. dbadmin" maxlength="80">
          </div>
          <div>
            <label for="body">Message</label>
            <textarea id="body" name="body" placeholder="Say something — it gets written to MySQL on the DB tier…" maxlength="500" required></textarea>
          </div>
        </div>
        <div class="actions"><button type="submit">Post message</button></div>
      </form>
    </div>

    <h2>Recent messages</h2>
    {% if messages %}
      {% for m in messages %}
        <div class="msg">
          <div class="meta"><span class="who">{{ m.author }}</span><span>{{ m.created }} UTC</span></div>
          <div>{{ m.body }}</div>
        </div>
      {% endfor %}
    {% else %}
      <div class="empty">No messages yet. Post the first one above.</div>
    {% endif %}

    <footer>
      Served from the web subnet · data persisted on the private DB subnet ·
      health endpoint at <code>/healthz</code>
    </footer>
  </div>
</body>
</html>
"""


# ----------------------------------------------------------------------------
# Entrypoint
# ----------------------------------------------------------------------------
if __name__ == "__main__":
    try:
        init_db()
        print(f"[app] DB initialised on {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    except Exception as exc:  # noqa: BLE001
        print(f"[app] WARNING: could not initialise DB yet: {exc}")
        print("[app] The app will still start; fix NSG/DB and refresh the page.")
    app.run(host="0.0.0.0", port=APP_PORT)
