import logging
import os

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient
from flask import Flask, Response

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Set this App Setting to the complete URL of the HTML blob.
# Example: https://<account>.blob.core.windows.net/<container>/index.html
BLOB_URL = os.environ.get("BLOB_URL")

# Credential chain uses the Web App's managed identity in Azure.
# No storage account key or connection string is required.
credential = DefaultAzureCredential()


@app.get("/")
def home():
    if not BLOB_URL:
        return Response(
            "BLOB_URL app setting is missing. Configure it in the Web App.",
            status=500,
            mimetype="text/plain",
        )

    try:
        blob = BlobClient.from_blob_url(BLOB_URL, credential=credential)
        html = blob.download_blob().readall()
        return Response(html, status=200, mimetype="text/html; charset=utf-8")
    except Exception:
        app.logger.exception("Could not read the HTML blob using managed identity")
        return Response(
            "Unable to load the page from Azure Blob Storage. "
            "Check the Web App identity, Storage Blob Data Reader role, "
            "BLOB_URL setting, and storage network rules.",
            status=500,
            mimetype="text/plain",
        )


@app.get("/health")
def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    # Local development only. Azure App Service uses Gunicorn via startup command.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
