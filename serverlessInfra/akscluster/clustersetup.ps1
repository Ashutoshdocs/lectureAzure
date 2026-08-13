############################################################
# AKS CLUSTER CREATION - AZURE CLI (PowerShell)
############################################################

# Login to Azure
az login

# Select Subscription
az account set --subscription "<SUBSCRIPTION_NAME_OR_ID>"

############################################################
# VARIABLES
############################################################

$RG="RG-AKS-DEMO"
$LOCATION="centralindia"
$AKSNAME="aks-demo-cluster"
$NODECOUNT=2
$VMSIZE="Standard_B2s"

############################################################
# CREATE RESOURCE GROUP
############################################################

az group create `
    --name $RG `
    --location $LOCATION

############################################################
# CREATE AKS CLUSTER
############################################################

az aks create `
    --resource-group $RG `
    --name $AKSNAME `
    --node-count $NODECOUNT `
    --node-vm-size $VMSIZE `
    --generate-ssh-keys `
    --network-plugin azure `
    --load-balancer-sku standard

############################################################
# DOWNLOAD KUBECONFIG TO CURRENT DIRECTORY
############################################################

# Creates a kubeconfig file named "config"
# in the current working directory.

az aks get-credentials `
    --resource-group $RG `
    --name $AKSNAME `
    --file .\config `
    --overwrite-existing

############################################################
# USE THE LOCAL KUBECONFIG
############################################################

# Tell kubectl to use the kubeconfig
# from the current folder.

$env:KUBECONFIG=".\config"

############################################################
# VERIFY KUBECONFIG
############################################################

echo "KUBECONFIG:"
echo $env:KUBECONFIG

############################################################
# VERIFY CLUSTER
############################################################

kubectl config current-context

kubectl cluster-info

kubectl get nodes

kubectl get pods -A

############################################################
# OPEN PROJECT IN VISUAL STUDIO CODE
############################################################

# Opens the current folder.

code .

############################################################
# OPEN THE KUBECONFIG FILE
############################################################

code .\config

############################################################
# VS CODE SETUP (ONE-TIME)
############################################################

# Install Extensions:
#
# ✓ Kubernetes (Microsoft)
# ✓ YAML (Red Hat)
# ✓ Docker (Microsoft) - Optional
#
# Ctrl + Shift + P
# Kubernetes: Set Kubeconfig
#
# Select:
# .\config

############################################################
# COMMON KUBECTL COMMANDS
############################################################

kubectl get ns

kubectl get all -A

kubectl get svc -A

kubectl get deploy -A

kubectl get ingress -A

############################################################
# PORT FORWARD EXAMPLE
############################################################

# kubectl port-forward svc/<SERVICE_NAME> 8080:80

############################################################
# OPEN POD SHELL
############################################################

# kubectl get pods
# kubectl exec -it <POD_NAME> -- /bin/sh

############################################################
# SHOW CLUSTER INFORMATION
############################################################

az aks show `
    --resource-group $RG `
    --name $AKSNAME `
    --output table

############################################################
# SHOW NODE POOLS
############################################################

az aks nodepool list `
    --resource-group $RG `
    --cluster-name $AKSNAME `
    --output table

############################################################
# SHOW KUBERNETES VERSION
############################################################

kubectl version

############################################################
# SHOW CLUSTER VERSION
############################################################

az aks show `
    --resource-group $RG `
    --name $AKSNAME `
    --query kubernetesVersion `
    --output tsv

############################################################
# SCALE CLUSTER (UNCOMMENT WHEN NEEDED)
############################################################

# Increase nodes to 3
# az aks scale `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --node-count 3

# Increase nodes to 5
# az aks scale `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --node-count 5

# Increase nodes to 10
# az aks scale `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --node-count 10

############################################################
# SCALE A SPECIFIC NODE POOL
############################################################

# az aks nodepool scale `
#     --resource-group $RG `
#     --cluster-name $AKSNAME `
#     --name nodepool1 `
#     --node-count 5

############################################################
# ENABLE CLUSTER AUTOSCALER
############################################################

# az aks update `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --enable-cluster-autoscaler `
#     --min-count 2 `
#     --max-count 10

############################################################
# DISABLE CLUSTER AUTOSCALER
############################################################

# az aks update `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --disable-cluster-autoscaler

############################################################
# UPGRADE KUBERNETES VERSION
############################################################

# View Available Upgrades
#
# az aks get-upgrades `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --output table

# Upgrade
#
# az aks upgrade `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --kubernetes-version <VERSION>

############################################################
# RESET TO DEFAULT KUBECONFIG
############################################################

# Remove custom kubeconfig
#
# Remove-Item Env:\KUBECONFIG

# OR use the default kubeconfig
#
# $env:KUBECONFIG="$HOME\.kube\config"

############################################################
# DELETE AKS CLUSTER
############################################################

# az aks delete `
#     --resource-group $RG `
#     --name $AKSNAME `
#     --yes `
#     --no-wait

############################################################
# DELETE RESOURCE GROUP
############################################################

# az group delete `
#     --name $RG `
#     --yes `
#     --no-wait

############################################################
# PROJECT FOLDER STRUCTURE
############################################################

# AKS-Demo/
#
# ├── create-aks.ps1
# ├── config
# ├── deployment.yaml
# ├── service.yaml
# ├── ingress.yaml
# └── README.md
#
# Everything required for the AKS demo remains in a
# single folder, making it easy to copy, archive, or
# share with students.