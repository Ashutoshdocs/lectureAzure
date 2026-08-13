from flask import Flask, redirect, session, url_for, request
from werkzeug.middleware.proxy_fix import ProxyFix

import msal
import uuid

app = Flask(__name__)

app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

app.secret_key = "super-secret-key"
app.config["SESSION_COOKIE_SECURE"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
CLIENT_ID = ""
CLIENT_SECRET = ""
TENANT_ID = ""

AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"

REDIRECT_PATH = "/getAToken"

SCOPE = ["User.Read"]

@app.route("/")
def index():
    if not session.get("user"):
        return redirect("/login")

    return f"""
    <h1>Welcome {session['user']['name']}</h1>
    <h2>Azure Enterprise Application Login Successful</h2>
    """

@app.route("/login")
def login():
    session["state"] = str(uuid.uuid4())

    auth_url = _build_msal_app().get_authorization_request_url(
        SCOPE,
        state=session["state"],
        redirect_uri=url_for("authorized", _external=True, _scheme='https')
    )

    return redirect(auth_url)

@app.route(REDIRECT_PATH)
def authorized():

    if request.args.get("state") != session.get("state"):
        return "State mismatch"

    result = _build_msal_app().acquire_token_by_authorization_code(
        request.args["code"],
        scopes=SCOPE,
        redirect_uri=url_for("authorized", _external=True, _scheme='https')
    )

    if "error" in result:
        return result.get("error_description")

    session["user"] = result.get("id_token_claims")

    return redirect("/")

def _build_msal_app():
    return msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=AUTHORITY,
        client_credential=CLIENT_SECRET,
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
