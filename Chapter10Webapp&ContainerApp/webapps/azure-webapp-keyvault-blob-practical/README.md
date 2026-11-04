# Azure App Service + Key Vault + Managed Identity + Blob Storage

## 1. Objective and architecture

The Storage Account connection string is stored in Azure Key Vault. The Web App
uses its system-assigned managed identity to read that secret at runtime. It then
uses the retrieved connection string to download a private HTML blob.

```text
Browser
  |
  v
Azure App Service (Python / Flask)
  |
  | System-assigned Managed Identity + Entra ID token
  v
Azure Key Vault
  |
  | Secret: storage-connection-string
  v
App Service receives secret in memory
  |
  | Storage SDK uses connection string
  v
Azure Blob Storage (private container) -> index.html
```

**Important:** The connection string is not in source code or Web App App Settings.
It is still a credential; Key Vault protects it at rest and controls access to it.

## 2. Prerequisites and variables

Requirements: Azure CLI, `az login`, Bash (Git Bash / Ubuntu / Cloud Shell), and
permissions to create resources and assign Azure RBAC roles.

This lab uses B1 Linux to avoid the F1 quota issue encountered in the earlier lab.
B1 is paid; check current Central India pricing before deployment.

```bash
az account show --output table

LOCATION="centralindia"
RG="rg-webapp-kv-blob-demo"
PLAN="plan-webapp-kv-blob-demo"
WEBAPP="web-kv-blob-<YOUR-UNIQUE-SUFFIX>"
STG="stgkv<YOUR-UNIQUE-SUFFIX>"
KV="kv-webapp-<YOUR-UNIQUE-SUFFIX>"
CONTAINER="privateweb"
SECRET_NAME="storage-connection-string"
```

Replace the suffix with unique lowercase letters/numbers. Storage names must be
3-24 lowercase alphanumeric characters. Key Vault names must be globally unique.
Web App names must also be globally unique.

## 3. Create Resource Group and Storage Account

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
```

Create the private container and upload the HTML using your signed-in Azure identity.
These commands do not use a connection string or account key:

```bash
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

Your signed-in user needs data-plane permissions such as Storage Blob Data Contributor
to upload the file.

## 4. Create Key Vault with Azure RBAC

```bash
az keyvault create \
  --name "$KV" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --enable-rbac-authorization true

KV_ID=$(az keyvault show \
  --name "$KV" \
  --resource-group "$RG" \
  --query id --output tsv)
```

Grant the signed-in user permission to create secrets. This role is for the lab
operator, not the Web App:

```bash
MY_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

az role assignment create \
  --assignee-object-id "$MY_OBJECT_ID" \
  --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope "$KV_ID"
```

Allow time for role assignment propagation before setting the secret.

## 5. Store the Storage connection string in Key Vault

The CLI retrieves the connection string and passes it directly to Key Vault.
`--output none` prevents the secret value from being printed by the set command.

```bash
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
  --name "$STG" \
  --resource-group "$RG" \
  --query connectionString \
  --output tsv)

az keyvault secret set \
  --vault-name "$KV" \
  --name "$SECRET_NAME" \
  --value "$STORAGE_CONNECTION_STRING" \
  --output none

unset STORAGE_CONNECTION_STRING
```

The value exists briefly in the current shell variable so it can be sent to Key Vault.
Do not echo it, paste it into source code, or save it in a file.

## 6. Create App Service Plan and Python Web App

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

## 7. Enable system-assigned Managed Identity

```bash
az webapp identity assign \
  --name "$WEBAPP" \
  --resource-group "$RG"

PRINCIPAL_ID=$(az webapp identity show \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --query principalId --output tsv)

echo "Web App identity principal ID: $PRINCIPAL_ID"
```

Azure manages the identity credentials and token lifecycle.

## 8. Grant the Web App permission to read Key Vault secrets

```bash
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID"
```

`Key Vault Secrets User` permits reading secret contents. A generic Azure Reader
role is not sufficient. Wait a few minutes for RBAC propagation.

## 9. Configure non-secret Web App settings

Retrieve the secret identifier (URI). This is not the secret value:

```bash
SECRET_URI=$(az keyvault secret show \
  --vault-name "$KV" \
  --name "$SECRET_NAME" \
  --query id --output tsv)

echo "$SECRET_URI"
```

Configure only the URI and blob identifiers in App Service:

```bash
az webapp config appsettings set \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --settings \
    KEY_VAULT_SECRET_URI="$SECRET_URI" \
    STORAGE_SECRET_NAME="$SECRET_NAME" \
    BLOB_CONTAINER="$CONTAINER" \
    BLOB_NAME="index.html" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
  --output none
```

No connection string or Storage Account key is placed in App Settings.

Configure the startup command:

```bash
az webapp config set \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --startup-file "gunicorn --bind=0.0.0.0:8000 --timeout 600 app:app"
```

## 10. Deploy the application

Run from the project root (the directory containing `app.py`):

```bash
zip -r app.zip app.py requirements.txt

az webapp deploy \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --src-path app.zip \
  --type zip
```

The build setting enables Azure build automation to install `requirements.txt`.

## 11. Test

```bash
az webapp show \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --query state --output tsv

curl -i "https://${WEBAPP}.azurewebsites.net/health"
curl -i "https://${WEBAPP}.azurewebsites.net/"
```

The root page should display the HTML stored in Blob Storage. Opening the blob URL
directly should fail for anonymous users because the container is private.

## 12. Verify the security design

List only setting names (not values):

```bash
az webapp config appsettings list \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --query "[].name" --output table
```

Expected settings include `KEY_VAULT_SECRET_URI`, `STORAGE_SECRET_NAME`,
`BLOB_CONTAINER`, and `BLOB_NAME`. There should be no Storage connection string
or account key in App Settings.

Verify identity and role:

```bash
az webapp identity show \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --output json

az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --scope "$KV_ID" \
  --output table
```

Avoid running `az keyvault secret show --query value` during a screen share; it
would reveal the secret.

## 13. Troubleshooting

Enable and tail application logs:

```bash
az webapp log config \
  --name "$WEBAPP" \
  --resource-group "$RG" \
  --application-logging filesystem \
  --level information

az webapp log tail --name "$WEBAPP" --resource-group "$RG"
```

Common causes of HTTP 500:
1. Managed Identity is not enabled.
2. `Key Vault Secrets User` is missing or RBAC has not propagated.
3. Secret name or Key Vault secret URI is incorrect.
4. Secret creation failed.
5. Storage firewall/network rules prevent the Web App from connecting.
6. Python packages did not install during deployment.

Managed Identity does not bypass Key Vault firewalls. A Storage connection string
does not bypass Storage firewalls either. This lab assumes both services are
network-accessible from the Web App. Private endpoints require App Service VNet
Integration, private endpoints, and correct private DNS configuration.

## 14. Cleanup

This deletes the resource group and all resources inside it:

```bash
az group delete --name "$RG" --yes --no-wait
```

## 15. Teaching questions and gotchas

1. Why does the Web App need Managed Identity? To authenticate to Key Vault.
2. Which role allows secret retrieval? `Key Vault Secrets User`.
3. Is `KEY_VAULT_SECRET_URI` a secret? No; it identifies the secret.
4. Does Key Vault automatically grant Storage access? No. The app retrieves the
   connection string and then uses it to authenticate to Storage.
5. How is this different from the previous practical? Previously, Managed Identity
   accessed Blob Storage directly using `Storage Blob Data Reader`. Here, Managed
   Identity accesses Key Vault; the Storage SDK then uses the connection string.
6. What is the trade-off? The credential is protected at rest in Key Vault, but
   the app handles it in memory. Prefer direct Managed Identity access to Blob
   Storage when possible unless secret retrieval is the learning objective.

## 16. Comparison

| Area | Previous practical | This practical |
|---|---|---|
| App authentication to Storage | Managed Identity | Connection string |
| Secret stored in Key Vault | No | Yes |
| App authentication to Key Vault | Not needed | Managed Identity |
| Key Vault RBAC | Not needed | Key Vault Secrets User |
| Storage RBAC for Web App | Storage Blob Data Reader | Not required for connection-string auth |
| Connection string in App Settings | No | No |
