"""Shared-disk demo frontend.

Lives on the shared disk (/mnt/shared/app) and talks to the MySQL instance
whose data directory is also on the shared disk. Shows which VM is serving.
"""
import os
import socket

import pymysql
from flask import Flask, redirect, render_template_string, request

app = Flask(__name__)
HOST = socket.gethostname()


def db():
    return pymysql.connect(
        unix_socket="/var/run/mysqld/mysqld.sock",
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        database=os.environ.get("DB_NAME", "demo"),
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Shared Disk Demo</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 16px;background:#f5f7fa;color:#1f2933}
 .badge{display:inline-block;padding:8px 16px;border-radius:999px;background:#0b6bcb;color:#fff;font-weight:600;font-size:18px}
 .card{background:#fff;border-radius:10px;padding:20px;margin-top:20px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
 input[type=text]{width:70%;padding:10px;border:1px solid #cbd2d9;border-radius:6px}
 button{padding:10px 18px;border:0;border-radius:6px;background:#0b6bcb;color:#fff;cursor:pointer}
 table{width:100%;border-collapse:collapse} th,td{text-align:left;padding:8px;border-bottom:1px solid #e4e7eb}
 .err{color:#b42318} small{color:#616e7c}
</style></head><body>
<h1>Azure Shared Disk Demo</h1>
<p>Served by: <span class="badge">{{ host }}</span></p>
<p><small>App code, MySQL data &amp; config all live on one Azure shared managed disk.</small></p>
{% if error %}<div class="card err">Database error: {{ error }}</div>{% endif %}
<div class="card">
 <form method="post"><input type="text" name="message" placeholder="Write a note..." required maxlength="500">
 <button>Save</button></form>
</div>
<div class="card"><h3>Notes ({{ notes|length }})</h3>
<table><tr><th>#</th><th>Message</th><th>Written by</th><th>Time</th></tr>
{% for n in notes %}<tr><td>{{ n.id }}</td><td>{{ n.message }}</td><td>{{ n.written_by }}</td><td>{{ n.created_at }}</td></tr>{% endfor %}
</table></div>
</body></html>"""


@app.route("/", methods=["GET", "POST"])
def index():
    error, notes = None, []
    try:
        conn = db()
        with conn.cursor() as cur:
            if request.method == "POST":
                msg = request.form.get("message", "").strip()[:500]
                if msg:
                    cur.execute(
                        "INSERT INTO notes (message, written_by) VALUES (%s, %s)",
                        (msg, HOST),
                    )
                conn.close()
                return redirect("/")
            cur.execute("SELECT * FROM notes ORDER BY id DESC")
            notes = cur.fetchall()
        conn.close()
    except Exception as exc:  # show the failure on the page during the demo
        error = str(exc)
    return render_template_string(PAGE, host=HOST, notes=notes, error=error)


@app.route("/health")
def health():
    try:
        conn = db()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return {"status": "ok", "node": HOST}, 200
    except Exception as exc:
        return {"status": "down", "node": HOST, "error": str(exc)}, 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 80)))
