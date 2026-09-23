"""Azure Function: rotates a Key Vault secret when SecretNearExpiry fires."""
import logging
import secrets
from datetime import datetime, timedelta, timezone

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

app = func.FunctionApp()


@app.event_grid_trigger(arg_name="event")
def rotate_secret(event: func.EventGridEvent):
    data = event.get_json()
    vault, name = data["VaultName"], data["ObjectName"]
    logging.info("Rotation triggered by %s for %s/%s", event.event_type, vault, name)

    client = SecretClient(f"https://{vault}.vault.azure.net", DefaultAzureCredential())
    current = client.get_secret(name)
    tags = current.properties.tags or {}
    days = int(tags.get("rotationDays", "90"))

    # For a real credential (DB password, API key), update the backing
    # system first, then store the new value in Key Vault.
    new_value = secrets.token_urlsafe(32)

    new = client.set_secret(
        name, new_value,
        expires_on=datetime.now(timezone.utc) + timedelta(days=days),
        tags=tags,
    )
    logging.info("Rotated %s -> version %s", name, new.properties.version)
