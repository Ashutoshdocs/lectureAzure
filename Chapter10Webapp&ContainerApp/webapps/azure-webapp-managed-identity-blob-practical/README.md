# Practical: Azure App Service reads a private HTML blob using Managed Identity

## 1. Objective

Build this flow:

```text
Browser
   |
   | HTTPS request
   v
Azure App Service (Python / Flask)
   |
   | System-assigned Managed Identity
   | Microsoft Entra ID token
   v
Azure Blob Storage (private container)
   |
   v
storage-content/index.html
```

The HTML file is private. The browser does **not** access Blob Storage directly. The
App Service retrieves the HTML file server-side and returns it to the browser.

**Security requirement:** Do not use a storage connection string, account key, or
SAS token anywhere in this practical. The app uses `DefaultAzureCredential` and
the Web App's system-assigned managed identity.

## 2. Prerequisites

- Azure CLI installed and logged in: `az login`
- An Azure subscription with permission to create resources and assign Azure RBAC roles
- Bash shell (Azure Cloud Shell or Ubuntu VM)
- Python is not required locally for deployment; Azure installs `requirements.txt`

Choose globally unique names. Run the commands in the same Bash session.

## 3. Set variables

```bash
az account show --output table

LOCATION="centralindia"
RG="rg-webapp-mi-blob-demo"
PLAN="plan-webapp-mi-blob-demo"
WEBAPP="web-mi-blob-<YOUR-UNIQUE-SUFFIX>"
STG="stgmi<YOUR-UNIQUE-SUFFIX>"
CONTAINER="privateweb"
```

Replace `<YOUR-UNIQUE-SUFFIX>` with lowercase letters/numbers. Storage account names
must be 3-24 characters, lowercase letters and numbers only. Web App names must be
globally unique.

## 4. Create the resource group, Storage Account, container, and upload HTML

```bash
az group create --name "$RG" --location "$LOCATION"

az storage account create \
  --name "$STG" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

az storage container create \
  --name "$CONTAINER" \
  --account-name "$STG" \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "index.html" \
  --file "storage-content/index.html" \
  --auth-mode login \
  --overwrite true
```

`--auth-mode login` uses your signed-in Azure identity for the upload. It does not
use a storage account key or connection string. Your user must have suitable data
permissions, such as Storage Blob Data Contributor, on the storage account.

## 5. Create the App Service plan and Python Web App

```bash
az appservice plan create \
  --name "$PLAN" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --is-linux \
  --sku B1

az webapp create \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --plan "$PLAN" \
  --runtime "PYTHON:3.11"
```

For a cost-conscious lab, you can use a supported lower tier if available in your
region, but ensure it supports the features required for your exercise.

## 6. Enable system-assigned managed identity

```bash
az webapp identity assign \
  --name "$WEBAPP" \
  --resource-group "$RG"

PRINCIPAL_ID=$(az webapp identity show \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --query principalId \
  --output tsv)

STORAGE_ID=$(az storage account show \
  --name "$STG" \
  --resource-group "$RG" \
  --query id \
  --output tsv)

echo "Web App managed identity principal: $PRINCIPAL_ID"
echo "Storage account resource ID: $STORAGE_ID"
```

The system-assigned identity is an Entra service principal representing this Web App.
Azure manages its credentials and token lifecycle.

## 7. Grant read-only access to Blob Storage

```bash
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "$STORAGE_ID"
```

**Important:** `Storage Blob Data Reader` is a data-plane role. A generic `Reader`
role on the Storage Account is not sufficient to download blob contents.

Role assignments can take a few minutes to propagate.

## 8. Configure the Blob URL and startup command

The URL is an address, not a credential. The container remains private.

```bash
BLOB_URL="https://${STG}.blob.core.windows.net/${CONTAINER}/index.html"

az webapp config appsettings set \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --settings \
    BLOB_URL="$BLOB_URL" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
    WEBSITE_HTTPLOGGING_ENABLED=true

az webapp config set \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --startup-file "gunicorn --bind=0.0.0.0:8000 --timeout 600 app:app"
```

The Python app uses the URL with `BlobClient.from_blob_url(..., credential=DefaultAzureCredential())`.
The SDK requests an Entra token from the App Service managed identity endpoint.

## 9. Deploy the application files

Run this from the practical's root directory (the directory containing `app.py`).

```bash
zip -r app.zip app.py requirements.txt
az webapp deploy \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --src-path app.zip \
  --type zip
```

If `zip` is not installed on Ubuntu:

```bash
sudo apt-get update && sudo apt-get install -y zip
```

Deployment build can take a few minutes because Azure installs the Python packages.

## 10. Test

```bash
az webapp browse --name "$WEBAPP" --resource-group "$RG"
```

Or:

```bash
curl -i "https://${WEBAPP}.azurewebsites.net/"
curl -i "https://${WEBAPP}.azurewebsites.net/health"
```

Expected:
- `/` displays the HTML page whose source is the private blob.
- `/health` returns `{"status":"healthy"}`.
- Opening the blob URL directly in a private/incognito browser should return an
  authorization error because anonymous blob access is disabled.

## 11. Troubleshooting

### HTTP 500: unable to load page

Check the app logs:

```bash
az webapp log config \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --application-logging filesystem \
  --level information

az webapp log tail --name "$WEBAPP" --resource-group "$RG"
```

Check identity and role assignment:

```bash
az webapp identity show --name "$WEBAPP" --resource-group "$RG" --output json

az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --scope "$STORAGE_ID" \
  --output table
```

Check the configured URL:

```bash
az webapp config appsettings list \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --query "[?name=='BLOB_URL'].value" \
  --output tsv
```

Common causes:
1. RBAC role assignment has not propagated yet.
2. `BLOB_URL` has a typo or points to the wrong container/blob.
3. The container or blob does not exist.
4. Storage firewall/private endpoint rules prevent the Web App from reaching Storage.
5. The Web App deployment did not install packages from `requirements.txt`.

### Important networking note

This practical assumes the Storage Account allows network access from the Web App.
If you configure Storage networking to allow selected networks only, you must also
configure a supported connectivity path (for example, App Service VNet Integration
and a Storage private endpoint with correct private DNS). Managed Identity solves
authentication/authorization; it does not bypass network firewalls.

## 12. Verify that no key or connection string is used

Search the project:

```bash
grep -RniE "AccountKey=|DefaultEndpointsProtocol=|AZURE_STORAGE_CONNECTION_STRING|sas" \
  --exclude=README.md .
```

The application should contain:
- `DefaultAzureCredential`
- `BlobClient.from_blob_url`
- `BLOB_URL` (URL only)

It should **not** contain:
- Storage account keys
- Storage connection strings
- SAS tokens

## 13. Cleanup

This deletes the entire lab resource group and all resources inside it:

```bash
az group delete --name "$RG" --yes --no-wait
```

## 14. Teaching explanation

- **Authentication:** Managed Identity proves *which identity* the Web App is.
- **Authorization:** `Storage Blob Data Reader` decides *what that identity can do*.
- **Blob URL:** Identifies the file; it is not a password or access token.
- **Private container:** Prevents anonymous users from reading the file directly.
- **App Service:** Acts as the trusted middle tier. It obtains an Entra token and
  downloads the HTML from Blob Storage on behalf of the browser.

A useful classroom test is to remove the role assignment, wait for propagation, and
refresh the Web App. The page should fail to load from Storage. Re-add the role and
retry after RBAC propagation.
