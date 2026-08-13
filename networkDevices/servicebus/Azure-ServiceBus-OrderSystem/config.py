"""Central configuration for the Order Processing System.

All values can be overridden with environment variables so you never have to
hard-code secrets. On the VM, the simplest path is:

    export SERVICE_BUS_CONNECTION_STRING="Endpoint=sb://...;SharedAccessKey=..."

Alternatively, paste the connection string into the default below (fine for a
classroom demo, not for production).
"""
import os

# --- Azure Service Bus -------------------------------------------------------
SERVICE_BUS_CONNECTION_STRING = os.getenv(
    "SERVICE_BUS_CONNECTION_STRING",
    "PASTE_YOUR_CONNECTION_STRING_HERE",
)
QUEUE_NAME = os.getenv("QUEUE_NAME", "orders")

# --- Database ----------------------------------------------------------------
DB_PATH = os.getenv(
    "DB_PATH",
    os.path.join(os.path.dirname(__file__), "database", "orders.db"),
)

# --- Worker behaviour (tweak live during the demo) ---------------------------
# Seconds the worker "works" on each order. Raise to 8-10 to show queue buffering.
PROCESS_SECONDS = float(os.getenv("PROCESS_SECONDS", "2"))
# Set to "1" to force every order to fail -> demonstrates retries + dead-letter.
FAIL_MODE = os.getenv("FAIL_MODE", "0") == "1"

# --- Web ---------------------------------------------------------------------
FLASK_HOST = os.getenv("FLASK_HOST", "0.0.0.0")
FLASK_PORT = int(os.getenv("FLASK_PORT", "5000"))


def is_connection_configured() -> bool:
    return bool(
        SERVICE_BUS_CONNECTION_STRING
        and not SERVICE_BUS_CONNECTION_STRING.startswith("PASTE_")
    )
