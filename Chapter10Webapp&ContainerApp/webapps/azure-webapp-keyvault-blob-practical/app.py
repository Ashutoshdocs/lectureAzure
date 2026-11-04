import logging
import os

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient
from flask import Flask, Response

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

KEY_VAULT_SECRET_URI = os.environ.get("KEY_VAULT_SECRET_URI")
STORAGE_SECRET_NAME = os.environ.get("STORAGE_SECRET_NAME", "storage-connection-string")
BLOB_CONTAINER = os.environ.get("BLOB_CONTAINER", "privateweb")
BLOB_NAME = os.environ.get("BLOB_NAME", "index.html")

# In Azure App Service, this resolves to the system-assigned managed identity.
credential = DefaultAzureCredential()


def get_storage_connection_string():
    if not KEY_VAULT_SECRET_URI:
        raise RuntimeError("KEY_VAULT_SECRET_URI app setting is missing")

    vault_url = KEY_VAULT_SECRET_URI.split("/secrets/")[0]
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(STORAGE_SECRET_NAME).value


@app.get("/")
def home():
    try:
        # Fetch secret at runtime; do not store it in source code or App Settings.
        connection_string = get_storage_connection_string()
        service = BlobServiceClient.from_connection_string(connection_string)
        blob = service.get_blob_client(BLOB_CONTAINER, BLOB_NAME)
        html = blob.download_blob().readall()
        return Response(html, status=200, mimetype="text/html; charset=utf-8")
    except Exception:
        # Never log secret values or connection strings.
        app.logger.exception("Unable to retrieve HTML from private Blob Storage")
        return Response(
            "Unable to load page. Check Managed Identity, Key Vault RBAC, "
            "secret configuration, and Storage network access.",
            status=500,
            mimetype="text/plain",
        )


@app.get("/health")
def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
