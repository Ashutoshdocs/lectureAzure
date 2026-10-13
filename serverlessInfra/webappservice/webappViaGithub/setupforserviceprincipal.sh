
#!/usr/bin/env bash

set -euo pipefail
umask 077

# ============================================================
# CONFIGURATION
# ============================================================

RG="mywebtest"
LOCATION="centralindia"
SP_NAME="github-actions-webapp-deployer"
CREDENTIALS_FILE="azure-credentials.json"

# Prevent Git Bash from converting Azure resource IDs into paths
export MSYS_NO_PATHCONV=1

# ============================================================
# STEP 1: AZURE LOGIN
# ============================================================

echo "=========================================="
echo "Step 1: Azure login"
echo "=========================================="

az login

# ============================================================
# STEP 2: SELECT SUBSCRIPTION
# ============================================================

echo "=========================================="
echo "Step 2: Select Azure subscription"
echo "=========================================="

az account list \
  --query "[?state=='Enabled'].{Name:name,SubscriptionId:id}" \
  --output table

read -r -p "Enter your Azure Subscription ID: " SUBSCRIPTION_ID

if [[ -z "$SUBSCRIPTION_ID" ]]; then
    echo "ERROR: Subscription ID cannot be empty."
    exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"

TENANT_ID=$(az account show --query tenantId --output tsv)

echo "Selected subscription:"
az account show \
  --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
  --output table

# ============================================================
# STEP 3: SELECT PERMISSION SCOPE
# ============================================================

echo "=========================================="
echo "Step 3: Select permission scope"
echo "=========================================="

echo "1. Resource group scope: $RG only"
echo "2. Subscription scope: all resource groups"

read -r -p "Choose 1 or 2: " SCOPE_CHOICE

case "$SCOPE_CHOICE" in
    1)
        ROLE_SCOPE="resource-group"
        ;;
    2)
        ROLE_SCOPE="subscription"
        ;;
    *)
        echo "ERROR: Invalid selection."
        exit 1
        ;;
esac

# ============================================================
# STEP 4: CREATE OR VERIFY RESOURCE GROUP
# ============================================================

echo "=========================================="
echo "Step 4: Create or verify resource group"
echo "=========================================="

az group create \
  --name "$RG" \
  --location "$LOCATION" \
  --output table

RG_SCOPE=$(az group show \
  --name "$RG" \
  --query id \
  --output tsv)

EXPECTED_RG_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}"

if [[ "${RG_SCOPE,,}" != "${EXPECTED_RG_SCOPE,,}" ]]; then
    echo "ERROR: Resource group scope validation failed."
    echo "Expected: $EXPECTED_RG_SCOPE"
    echo "Received: $RG_SCOPE"
    exit 1
fi

if [[ "$ROLE_SCOPE" == "subscription" ]]; then
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
else
    SCOPE="$RG_SCOPE"
fi

echo "Resource group: $RG"
echo "Role assignment scope: $SCOPE"

# ============================================================
# STEP 5: FIND OR CREATE SERVICE PRINCIPAL
# ============================================================

echo "=========================================="
echo "Step 5: Find or create service principal"
echo "=========================================="

APP_ID=$(az ad app list \
  --display-name "$SP_NAME" \
  --query "[0].appId" \
  --output tsv)

if [[ -z "$APP_ID" || "$APP_ID" == "None" ]]; then
    echo "Creating application and service principal..."

    APP_ID=$(az ad sp create-for-rbac \
      --name "$SP_NAME" \
      --skip-assignment \
      --query appId \
      --output tsv)
else
    echo "Existing application found."
fi

if [[ -z "$APP_ID" || "$APP_ID" == "None" ]]; then
    echo "ERROR: Could not obtain application ID."
    exit 1
fi

SP_OBJECT_ID=$(az ad sp show \
  --id "$APP_ID" \
  --query id \
  --output tsv 2>/dev/null || true)

if [[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "None" ]]; then
    echo "Creating missing service principal..."

    SP_OBJECT_ID=$(az ad sp create \
      --id "$APP_ID" \
      --query id \
      --output tsv)
fi

echo "Application ID: $APP_ID"
echo "Service principal object ID: $SP_OBJECT_ID"

# ============================================================
# STEP 6: ASSIGN CONTRIBUTOR ROLE
# ============================================================

echo "=========================================="
echo "Step 6: Assign Contributor role"
echo "=========================================="

EXISTING_ASSIGNMENT=$(az role assignment list \
  --assignee "$SP_OBJECT_ID" \
  --scope "$SCOPE" \
  --query "[?roleDefinitionName=='Contributor'] | length(@)" \
  --output tsv)

if [[ "$EXISTING_ASSIGNMENT" == "0" ]]; then
    echo "Creating Contributor role assignment..."

    az role assignment create \
      --assignee-object-id "$SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "Contributor" \
      --scope "$SCOPE" \
      --output table
else
    echo "Contributor assignment already exists."
fi

# ============================================================
# STEP 7: GENERATE CLIENT SECRET
# ============================================================

echo "=========================================="
echo "Step 7: Generate client secret"
echo "=========================================="

echo "Generating a new client secret..."

# Capture stdout so the secret is not printed to the terminal.
# --append requests that existing credentials be retained.
CREDENTIALS_JSON=$(az ad app credential reset \
  --id "$APP_ID" \
  --display-name "github-actions-deployment" \
  --years 1 \
  --append \
  --output json)

CLIENT_SECRET=$(printf '%s' "$CREDENTIALS_JSON" | python -c '
import json, sys
print(json.load(sys.stdin)["password"])
')

unset CREDENTIALS_JSON

if [[ -z "$CLIENT_SECRET" ]]; then
    echo "ERROR: Client secret generation failed."
    exit 1
fi

# ============================================================
# STEP 8: CAPTURE COMPLETE GITHUB CREDENTIALS JSON
# ============================================================

echo "=========================================="
echo "Step 8: Save credentials to JSON file"
echo "=========================================="

export APP_ID CLIENT_SECRET SUBSCRIPTION_ID TENANT_ID

python - "$CREDENTIALS_FILE" <<'PY'
import json
import os
import sys

filename = sys.argv[1]

credentials = {
    "clientId": os.environ["APP_ID"],
    "clientSecret": os.environ["CLIENT_SECRET"],
    "subscriptionId": os.environ["SUBSCRIPTION_ID"],
    "tenantId": os.environ["TENANT_ID"],
    "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
    "resourceManagerEndpointUrl": "https://management.azure.com/",
    "activeDirectoryGraphResourceId": "https://graph.windows.net/",
    "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
    "galleryEndpointUrl": "https://gallery.azure.com/",
    "managementEndpointUrl": "https://management.core.windows.net/"
}

with open(filename, "w", encoding="utf-8") as file:
    json.dump(credentials, file, indent=2)
    file.write("\n")

print("Credentials saved successfully.")
print("Client secret was not printed.")
PY

unset CLIENT_SECRET

# Restrict file access where supported.
chmod 600 "$CREDENTIALS_FILE"

# ============================================================
# STEP 9: VERIFY RESOURCE GROUP
# ============================================================

echo "=========================================="
echo "Step 9: Verify resource group"
echo "=========================================="

az group show \
  --name "$RG" \
  --query "{Name:name,Location:location,ID:id}" \
  --output table

# ============================================================
# STEP 10: VERIFY ROLE ASSIGNMENT
# ============================================================

echo "=========================================="
echo "Step 10: Verify Contributor role"
echo "=========================================="

az role assignment list \
  --assignee "$SP_OBJECT_ID" \
  --scope "$SCOPE" \
  --query "[?roleDefinitionName=='Contributor'].{Role:roleDefinitionName,Principal:principalName,Scope:scope}" \
  --output table

# ============================================================
# COMPLETION
# ============================================================

echo
echo "=========================================="
echo "SCRIPT COMPLETED SUCCESSFULLY"
echo "=========================================="

echo "Resource Group : $RG"
echo "Location       : $LOCATION"
echo "Service Name   : $SP_NAME"
echo "Subscription   : $SUBSCRIPTION_ID"
echo "Permission     : $ROLE_SCOPE"
echo "Credentials    : $CREDENTIALS_FILE"

echo
echo "NEXT STEPS:"
echo "1. Open $CREDENTIALS_FILE locally."
echo "2. Copy the complete JSON contents."
echo "3. Open GitHub repository Settings."
echo "4. Go to Secrets and variables > Actions."
echo "5. Create or update AZURE_CREDENTIALS."
echo "6. Paste the JSON contents as the secret value."
echo
echo "Never commit the credentials file to Git."
echo "=========================================="
