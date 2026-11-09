#!/usr/bin/env bash
# Source this file with: source templates/lab-variables-bash.sh
export LOCATION="centralindia"
export RG="rg-azcli-training"
export VNET="vnet-azcli"
export SUBNET="snet-app"
export NSG="nsg-azcli"
export PIP="pip-azcli-vm"
export NIC="nic-azcli-vm"
export VM="vm-azcli-linux"
export STORAGE="stazcli$(openssl rand -hex 4)"
export PLAN="plan-azcli-demo"
export WEBAPP="webazcli$(openssl rand -hex 4)"
