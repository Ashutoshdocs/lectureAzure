"""
Secure Employee Portal — Microsoft Entra ID (Azure AD) SSO demo.

A small but realistic enterprise app that signs users in with Entra ID,
reads their real profile from Microsoft Graph, shows their group/app-role
assignments, and demonstrates a protected API call using the access token.
"""

import os
import uuid
import requests
import msal
from flask import (
    Flask, redirect, render_template, session, url_for, request, jsonify, abort
)
from werkzeug.middleware.proxy_fix import ProxyFix

import config

app = Flask(__name__)

# We sit behind nginx doing TLS termination, so trust one proxy hop for the
# X-Forwarded-Proto / X-Forwarded-Host headers. Without this, url_for(_external)
# would build http:// URLs and the redirect_uri would not match the app reg.
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

app.secret_key = config.SECRET_KEY
app.config.update(
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)


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
    """Redirect to /login if there is no signed-in user in the session."""
    from functools import wraps

    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user"):
            return redirect(url_for("login"))
        return view(*args, **kwargs)

    return wrapped


# ---------------------------------------------------------------------------
# Microsoft Graph
# ---------------------------------------------------------------------------
def graph_get(endpoint):
    """Call a Graph endpoint with the cached access token.

    Returns the parsed JSON on success, an {"error": ...} dict on a handled
    failure, or None if no usable token is available. Never raises, so a Graph
    hiccup degrades the page gracefully instead of 500-ing.
    """
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
    except Exception as exc:  # network error, token failure, etc.
        app.logger.warning("Graph call failed for %s: %s", endpoint, exc)
        return {"error": "graph_unavailable", "detail": str(exc)}


# ---------------------------------------------------------------------------
# Routes
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
    # CSRF protection: the state we sent must come back unchanged.
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


@app.route("/dashboard")
@login_required
def dashboard():
    import json
    claims = session["user"]

    # Real profile straight from Microsoft Graph.
    profile = graph_get("/me?$select=displayName,jobTitle,mail,userPrincipalName,"
                        "officeLocation,mobilePhone,department,preferredLanguage")

    # Roles come from the app-registration app roles assigned to the user,
    # surfaced in the ID token as the "roles" claim.
    roles = claims.get("roles", [])

    return render_template(
        "dashboard.html",
        claims=claims,
        claims_pretty=json.dumps(claims, indent=2, sort_keys=True),
        profile=profile or {},
        roles=roles,
        graph_ok=bool(profile and "error" not in profile),
    )


@app.route("/api/me")
@login_required
def api_me():
    """A protected JSON endpoint — demonstrates calling downstream APIs with the token."""
    data = graph_get("/me")
    if data is None:
        abort(401)
    return jsonify(data)


@app.route("/api/groups")
@login_required
def api_groups():
    """List the groups the signed-in user belongs to (needs GroupMember.Read.All)."""
    data = graph_get("/me/memberOf?$select=displayName,id")
    if data is None:
        abort(401)
    return jsonify(data)


@app.route("/logout")
def logout():
    session.clear()
    # Also sign the user out at Entra so the browser session is cleared.
    return redirect(
        f"{config.AUTHORITY}/oauth2/v2.0/logout"
        f"?post_logout_redirect_uri={url_for('index', _external=True, _scheme='https')}"
    )


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    # Dev only. In production run via gunicorn (see README / systemd unit).
    app.run(host="0.0.0.0", port=5000, debug=config.FLASK_DEBUG)
