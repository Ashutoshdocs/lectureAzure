
#!/usr/bin/env bash

set -euo pipefail

# Configuration
RG="mywebtest"
LOCATION="centralindia"
SP_NAME="github-actions-webapp-deployer"

echo "=========================================="
echo "Step 1: Azure login"
echo "=========================================="
az login

echo "=========================================="
echo "Step 2: Select Azure subscription"
echo "=========================================="
az account list --query "[?state=='Enabled'].{Name:name, SubscriptionId:id}" --output table

read -rp "Enter your Azure Subscription ID: " SUBSCRIPTION_ID

az account set --subscription "$SUBSCRIPTION_ID"

echo "Selected subscription:"
az account show --query "{Name:name, SubscriptionId:id}" --output table

echo "=========================================="
echo "Step 3: Create Resource Group"
echo "=========================================="
az group create  --name "$RG" --location "$LOCATION" --output table

echo "=========================================="
echo "Step 4: Get Resource Group scope"
echo "=========================================="
RG_SCOPE=$(az group show --name "$RG" --query id  --output tsv)

echo "Resource Group: $RG"
echo "Scope: $RG_SCOPE"

echo "=========================================="
echo "Step 5: Create Service Principal"
echo "=========================================="

CREDENTIALS=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor  --scopes "$RG_SCOPE"  --json-auth)

echo "=========================================="
echo "SUCCESS"
echo "=========================================="
echo "Resource Group created: $RG"
echo "Service Principal created: $SP_NAME"
echo
echo "Copy the following JSON into your GitHub repository secret:"
echo "Settings > Secrets and variables > Actions"
echo "Secret name: AZURE_CREDENTIALS"
echo
echo "$CREDENTIALS"
