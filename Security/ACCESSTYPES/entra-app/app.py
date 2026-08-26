"""
Secure Employee Portal — Microsoft Entra ID (Azure AD) SSO demo.

Signs users in with Entra ID, reads their real profile from Microsoft Graph,
shows app-role assignments, and gives each user a personal task board
(add / complete / reopen / delete) with live completed-vs-remaining counts.

Task storage is in-memory and per-user (keyed to the Entra object id), so it
resets when the app restarts — intentional for a demo.
"""

import os
import json
import uuid
import threading
from datetime import datetime, timezone

import requests
import msal
from flask import (
    Flask, redirect, render_template, session, url_for, request, jsonify, abort
)
from flask_session import Session
from werkzeug.middleware.proxy_fix import ProxyFix

import config

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

app = Flask(__name__)

# Behind nginx (TLS termination): trust one proxy hop for X-Forwarded-* so
# url_for(_external) builds https URLs matching the registered redirect_uri.
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

app.secret_key = config.SECRET_KEY
app.config.update(
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    # Server-side sessions: Entra tokens + MSAL cache exceed the browser's
    # ~4KB cookie limit, which otherwise causes a redirect loop.
    SESSION_TYPE="filesystem",
    SESSION_FILE_DIR=os.path.join(BASE_DIR, ".flask_session"),
    SESSION_PERMANENT=False,
)
Session(app)


# ---------------------------------------------------------------------------
# In-memory task store (per-user). Resets on restart — fine for a demo.
# Structure: { user_oid: [ {id, title, done, created, completed}, ... ] }
# ---------------------------------------------------------------------------
_TASKS = {}
_LOCK = threading.Lock()

_SEED = [
    "Complete security awareness training",
    "Submit Q3 timesheet",
    "Review and sign updated device policy",
]


def _now():
    return datetime.now(timezone.utc).isoformat()


def _user_key():
    """Stable per-user key from the ID-token claims (object id, then fallbacks)."""
    claims = session.get("user") or {}
    return claims.get("oid") or claims.get("sub") or claims.get("preferred_username")


def _get_tasks(key, seed_if_empty=True):
    with _LOCK:
        if key not in _TASKS:
            if seed_if_empty:
                _TASKS[key] = [
                    {"id": uuid.uuid4().hex, "title": t, "done": False,
                     "created": _now(), "completed": None}
                    for t in _SEED
                ]
            else:
                _TASKS[key] = []
        # return a shallow copy so callers can't mutate under the lock
        return list(_TASKS[key])


def _summary(tasks):
    total = len(tasks)
    done = sum(1 for t in tasks if t["done"])
    remaining = total - done
    pct = round((done / total) * 100) if total else 0
    return {"total": total, "done": done, "remaining": remaining, "percent": pct}


# ---------------------------------------------------------------------------
# MSAL helpers
# ---------------------------------------------------------------------------
def _load_cache():
    cache = msal.SerializableTokenCache()
    if session.get("token_cache"):
        cache.deserialize(session["token_cache"])
    return cache


def _save_cache(cache):
    if cache.has_state_changed:
        session["token_cache"] = cache.serialize()


def _build_msal_app(cache=None):
    return msal.ConfidentialClientApplication(
        config.CLIENT_ID,
        authority=config.AUTHORITY,
        client_credential=config.CLIENT_SECRET,
        token_cache=cache,
    )


def _build_auth_url(state):
    return _build_msal_app().get_authorization_request_url(
        config.SCOPE,
        state=state,
        redirect_uri=url_for("authorized", _external=True, _scheme="https"),
    )


def _get_token_from_cache(scopes):
    cache = _load_cache()
    app_ = _build_msal_app(cache=cache)
    accounts = app_.get_accounts()
    if accounts:
        result = app_.acquire_token_silent(scopes, account=accounts[0])
        _save_cache(cache)
        return result
    return None


def login_required(view):
    from functools import wraps

    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user"):
            # For API calls, return 401 JSON instead of an HTML redirect.
            if request.path.startswith("/api/"):
                abort(401)
            return redirect(url_for("login"))
        return view(*args, **kwargs)

    return wrapped


# ---------------------------------------------------------------------------
# Microsoft Graph
# ---------------------------------------------------------------------------
def graph_get(endpoint):
    """Call a Graph endpoint with the cached access token. Never raises."""
    try:
        token = _get_token_from_cache(config.SCOPE)
        if not token or "access_token" not in token:
            return None
        resp = requests.get(
            f"{config.GRAPH_ENDPOINT}{endpoint}",
            headers={"Authorization": "Bearer " + token["access_token"]},
            timeout=10,
        )
        if resp.status_code != 200:
            return {"error": resp.status_code, "detail": resp.text}
        return resp.json()
    except Exception as exc:
        app.logger.warning("Graph call failed for %s: %s", endpoint, exc)
        return {"error": "graph_unavailable", "detail": str(exc)}


# ---------------------------------------------------------------------------
# Auth routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    if not session.get("user"):
        return render_template("login.html")
    return redirect(url_for("dashboard"))


@app.route("/login")
def login():
    if session.get("user"):
        return redirect(url_for("dashboard"))
    session["state"] = str(uuid.uuid4())
    return redirect(_build_auth_url(session["state"]))


@app.route(config.REDIRECT_PATH)
def authorized():
    if request.args.get("state") != session.get("state"):
        return render_template("error.html",
                               message="State mismatch — possible CSRF. Please try signing in again."), 400
    if "error" in request.args:
        return render_template("error.html",
                               message=request.args.get("error_description", "Sign-in was cancelled or failed.")), 400
    if "code" not in request.args:
        return redirect(url_for("index"))

    cache = _load_cache()
    result = _build_msal_app(cache=cache).acquire_token_by_authorization_code(
        request.args["code"],
        scopes=config.SCOPE,
        redirect_uri=url_for("authorized", _external=True, _scheme="https"),
    )
    if "error" in result:
        return render_template("error.html",
                               message=result.get("error_description", "Token acquisition failed.")), 400

    session["user"] = result.get("id_token_claims")
    _save_cache(cache)
    return redirect(url_for("dashboard"))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(
        f"{config.AUTHORITY}/oauth2/v2.0/logout"
        f"?post_logout_redirect_uri={url_for('index', _external=True, _scheme='https')}"
    )


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
@app.route("/dashboard")
@login_required
def dashboard():
    claims = session["user"]
    profile = graph_get("/me?$select=displayName,jobTitle,mail,userPrincipalName,"
                        "officeLocation,mobilePhone,department,preferredLanguage")
    roles = claims.get("roles", [])
    tasks = _get_tasks(_user_key())

    return render_template(
        "dashboard.html",
        claims=claims,
        claims_pretty=json.dumps(claims, indent=2, sort_keys=True),
        profile=profile or {},
        roles=roles,
        graph_ok=bool(profile and "error" not in profile),
        summary=_summary(tasks),
    )


# ---------------------------------------------------------------------------
# Task API (all per-user, in-memory)
# ---------------------------------------------------------------------------
@app.route("/api/tasks", methods=["GET"])
@login_required
def list_tasks():
    tasks = _get_tasks(_user_key())
    return jsonify({"tasks": tasks, "summary": _summary(tasks)})


@app.route("/api/tasks", methods=["POST"])
@login_required
def add_task():
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return jsonify({"error": "Task title is required."}), 400
    if len(title) > 200:
        title = title[:200]

    key = _user_key()
    task = {"id": uuid.uuid4().hex, "title": title, "done": False,
            "created": _now(), "completed": None}
    with _LOCK:
        _TASKS.setdefault(key, []).append(task)
        tasks = list(_TASKS[key])
    return jsonify({"task": task, "summary": _summary(tasks)}), 201


@app.route("/api/tasks/<task_id>", methods=["PATCH"])
@login_required
def toggle_task(task_id):
    """Toggle done, or set explicitly via {"done": true/false}."""
    data = request.get_json(silent=True) or {}
    key = _user_key()
    with _LOCK:
        tasks = _TASKS.get(key, [])
        for t in tasks:
            if t["id"] == task_id:
                t["done"] = bool(data["done"]) if "done" in data else not t["done"]
                t["completed"] = _now() if t["done"] else None
                snapshot = list(tasks)
                return jsonify({"task": t, "summary": _summary(snapshot)})
    return jsonify({"error": "Task not found."}), 404


@app.route("/api/tasks/<task_id>", methods=["DELETE"])
@login_required
def delete_task(task_id):
    key = _user_key()
    with _LOCK:
        tasks = _TASKS.get(key, [])
        for i, t in enumerate(tasks):
            if t["id"] == task_id:
                tasks.pop(i)
                snapshot = list(tasks)
                return jsonify({"deleted": task_id, "summary": _summary(snapshot)})
    return jsonify({"error": "Task not found."}), 404


# ---------------------------------------------------------------------------
# Other protected API demos (unchanged)
# ---------------------------------------------------------------------------
@app.route("/api/me")
@login_required
def api_me():
    data = graph_get("/me")
    if data is None:
        abort(401)
    return jsonify(data)


@app.route("/api/groups")
@login_required
def api_groups():
    data = graph_get("/me/memberOf?$select=displayName,id")
    if data is None:
        abort(401)
    return jsonify(data)


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=config.FLASK_DEBUG)
