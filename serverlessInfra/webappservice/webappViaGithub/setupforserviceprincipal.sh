
#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

RG="mywebtest"
LOCATION="centralindia"
SP_NAME="github-actions-webapp-deployer"

# IMPORTANT:
# Prevent Git Bash from converting Azure resource IDs into
# Windows filesystem paths such as C:/Program Files/Git/...
export MSYS_NO_PATHCONV=1

# ============================================================
# STEP 1: AZURE LOGIN
# ============================================================

echo "=========================================="
echo "Step 1: Azure login"
echo "=========================================="

az login

# ============================================================
# STEP 2: SELECT AZURE SUBSCRIPTION
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

echo "Selected subscription:"
az account show \
  --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
  --output table

# ============================================================
# STEP 3: CREATE RESOURCE GROUP
# ============================================================

echo "=========================================="
echo "Step 3: Create Resource Group"
echo "=========================================="

az group create \
  --name "$RG" \
  --location "$LOCATION" \
  --output table

# ============================================================
# STEP 4: GET AND VALIDATE RESOURCE GROUP SCOPE
# ============================================================

echo "=========================================="
echo "Step 4: Get Resource Group scope"
echo "=========================================="

SCOPE=$(az group show \
  --name "$RG" \
  --query id \
  --output tsv)

echo "Resource Group: $RG"
echo "Scope: $SCOPE"

EXPECTED_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}"

if [[ "${SCOPE,,}" != "${EXPECTED_SCOPE,,}" ]]; then
    echo "ERROR: Resource group scope does not match."
    echo "Expected: $EXPECTED_SCOPE"
    echo "Received: $SCOPE"
    exit 1
fi

echo "Resource group scope validated successfully."

# ============================================================
# STEP 5: CREATE SERVICE PRINCIPAL
# ============================================================

echo "=========================================="
echo "Step 5: Create Service Principal"
echo "=========================================="

echo "Service Principal: $SP_NAME"
echo "Role: Contributor"
echo "Scope: $SCOPE"

echo "Creating service principal and role assignment..."

# This legacy output format is retained for compatibility
# with GitHub Actions workflows using AZURE_CREDENTIALS.
az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Contributor" \
  --scopes "$SCOPE" \
  --sdk-auth \
  --output json

echo
echo "Service principal creation command completed."

# ============================================================
# STEP 6: VERIFY RESOURCE GROUP
# ============================================================

echo "=========================================="
echo "Step 6: Verify Resource Group"
echo "=========================================="

az group show \
  --name "$RG" \
  --query "{Name:name,Location:location,ID:id}" \
  --output table

# ============================================================
# STEP 7: VERIFY CONTRIBUTOR ROLE ASSIGNMENT
# ============================================================

echo "=========================================="
echo "Step 7: Verify Contributor Role Assignment"
echo "=========================================="

az role assignment list \
  --scope "$SCOPE" \
  --all \
  --query "[?roleDefinitionName=='Contributor'].{Role:roleDefinitionName,Principal:principalName,Scope:scope}" \
  --output table

# ============================================================
# COMPLETION
# ============================================================

echo
echo "=========================================="
echo "SCRIPT COMPLETED"
echo "=========================================="
echo "Resource Group : $RG"
echo "Location       : $LOCATION"
echo "Service Name   : $SP_NAME"
echo "Subscription   : $SUBSCRIPTION_ID"
echo
echo "IMPORTANT:"
echo "Store the generated credentials securely."
echo "Never commit credentials or client secrets to GitHub."
echo "=========================================="
