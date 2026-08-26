"""
Configuration loaded from environment variables.

Nothing secret is hard-coded. Copy .env.example to .env, fill it in, and the
app / systemd unit will load it. This keeps client secrets out of source control.
"""

import os


def _require(name):
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"Missing required environment variable: {name}. "
            f"Copy .env.example to .env and fill it in."
        )
    return value


# --- Entra ID app registration ---
CLIENT_ID = _require("CLIENT_ID")
CLIENT_SECRET = _require("CLIENT_SECRET")
TENANT_ID = _require("TENANT_ID")

AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
REDIRECT_PATH = os.environ.get("REDIRECT_PATH", "/getAToken")

# Delegated Graph scopes the app requests.
# User.Read is enough for the basic demo. Add GroupMember.Read.All (and grant
# admin consent) if you want the /api/groups endpoint to work.
SCOPE = os.environ.get("SCOPE", "User.Read").split()

GRAPH_ENDPOINT = "https://graph.microsoft.com/v1.0"

# --- Flask ---
# Generate a strong one with:  python -c "import secrets; print(secrets.token_hex(32))"
SECRET_KEY = _require("FLASK_SECRET_KEY")
FLASK_DEBUG = os.environ.get("FLASK_DEBUG", "0") == "1"
