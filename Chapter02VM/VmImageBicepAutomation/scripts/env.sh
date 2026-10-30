#!/bin/bash
# Shared variables for the demo.
# Usage:  source ./scripts/env.sh

export SUB_ID=$(az account show --query id -o tsv)
export LOCATION="centralindia"

# Network (created manually in Step 1)
export RG="rg-image-demo"
export VNET="vnet-image-demo"
export SUBNET="snet-vms"

# Gallery
export GALLERY="galImageDemo"            # letters, digits, _ and . only
export IMAGE_DEF="nginx-ubuntu2204"
export PUBLISHER="DemoOrg"
export OFFER="NginxWeb"
export SKU="ubuntu2204-nginx"

export ADMIN_USER="azureuser"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub 2>/dev/null)"   # read by main.bicepparam

echo "Environment loaded: SUB_ID=$SUB_ID RG=$RG GALLERY=$GALLERY IMAGE_DEF=$IMAGE_DEF"
