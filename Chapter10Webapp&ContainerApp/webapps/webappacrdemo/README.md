# 🚀 WebApp Deployment — Docker → Azure Container Registry (ACR)

A static demo page served by NGINX, packaged as a Docker image, tagged and pushed to **Azure Container Registry**.

```
Code  →  docker build  →  docker tag  →  docker push  →  ACR  →  run anywhere
```

---

## 📁 Project structure

```
webappacrdemo/
├── index.html     # Demo page
├── Dockerfile     # nginx:alpine image serving index.html
└── README.md      # This guide
```

---

## ✅ Prerequisites

| Tool | Check |
|------|-------|
| Docker Desktop / Docker Engine | `docker --version` |
| Azure CLI | `az --version` |
| An Azure subscription | `az account show` |

> **Apple Silicon (M1/M2/M3) users:** Azure runs `linux/amd64`. Add `--platform linux/amd64` to `docker build`.

---

## 1️⃣ Set variables

Set these once so every command below works as-is.

**Bash / Linux / macOS / Git Bash**
```bash
RG=rg-webappdemo
LOCATION=centralindia
ACR_NAME=webappacr$RANDOM        # must be globally unique, lowercase letters+numbers, 5–50 chars
IMAGE=webappdeployment
TAG=v1
```

**PowerShell**
```powershell
$RG="rg-webappdemo"
$LOCATION="centralindia"
$ACR_NAME="webappacr$(Get-Random -Maximum 99999)"
$IMAGE="webappdeployment"
$TAG="v1"
```
> In PowerShell, write variables as `$RG` etc. in the commands below.

---

## 2️⃣ Build the image locally

```bash
docker build -t $IMAGE:$TAG .
docker images | grep $IMAGE
```

## 3️⃣ Test locally

```bash
docker run -d --name $IMAGE -p 8080:80 $IMAGE:$TAG
```

Open **http://localhost:8080** — you should see the demo page.

```bash
docker ps                      # container should show "healthy" after ~30s
docker rm -f $IMAGE            # stop & remove when done
```

---

## 4️⃣ Log in to Azure

```bash
az login
az account set --subscription "<your-subscription-name-or-id>"   # if you have more than one
```

## 5️⃣ Create a resource group

```bash
az group create --name $RG --location $LOCATION
```

## 6️⃣ Create the Azure Container Registry

```bash
az acr create \
  --resource-group $RG \
  --name $ACR_NAME \
  --sku Basic
```

Get the registry's login server (looks like `webappacr12345.azurecr.io`):

```bash
ACR_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)
echo $ACR_SERVER
```
PowerShell: `$ACR_SERVER = az acr show --name $ACR_NAME --query loginServer -o tsv`

## 7️⃣ Log Docker in to ACR

```bash
az acr login --name $ACR_NAME
```
Expected output: `Login Succeeded`

---

## 8️⃣ Tag the image for ACR

An image must be tagged with the registry's login server before it can be pushed.

```bash
docker tag $IMAGE:$TAG $ACR_SERVER/$IMAGE:$TAG
docker tag $IMAGE:$TAG $ACR_SERVER/$IMAGE:latest     # optional "latest" tag
```

```bash
docker images | grep $IMAGE
# webappdeployment                       v1      ...
# webappacr12345.azurecr.io/webappdeployment  v1      ...
# webappacr12345.azurecr.io/webappdeployment  latest  ...
```

## 9️⃣ Push to ACR

```bash
docker push $ACR_SERVER/$IMAGE:$TAG
docker push $ACR_SERVER/$IMAGE:latest
```

## 🔟 Verify the image in ACR

```bash
az acr repository list --name $ACR_NAME -o table
az acr repository show-tags --name $ACR_NAME --repository $IMAGE -o table
```

Or in the Azure Portal: **Container registries → your ACR → Services → Repositories → webappdeployment**.

---

## 🧪 Pull and run from ACR (proof it works)

```bash
docker rmi $ACR_SERVER/$IMAGE:$TAG          # remove local copy
docker pull $ACR_SERVER/$IMAGE:$TAG
docker run -d --name webapp-acr -p 8080:80 $ACR_SERVER/$IMAGE:$TAG
```
Open **http://localhost:8080**.

---

## 🔄 Releasing a new version (v2)

1. Edit `index.html` — change `Version 1.0` to `Version 2.0` (and the badge colour if you like).
2. Build, tag, push:

```bash
docker build -t $IMAGE:v2 .
docker tag  $IMAGE:v2 $ACR_SERVER/$IMAGE:v2
docker tag  $IMAGE:v2 $ACR_SERVER/$IMAGE:latest
docker push $ACR_SERVER/$IMAGE:v2
docker push $ACR_SERVER/$IMAGE:latest
```

3. `az acr repository show-tags --name $ACR_NAME --repository $IMAGE -o table` now lists `v1`, `v2`, `latest`.

---

## ⚡ Alternative: build in the cloud with `az acr build`

No local Docker needed — ACR builds and stores the image in one step:

```bash
az acr build --registry $ACR_NAME --image $IMAGE:$TAG .
```

---

## ☁️ Optional: run it on Azure Container Instances

```bash
az acr update --name $ACR_NAME --admin-enabled true
ACR_USER=$(az acr credential show -n $ACR_NAME --query username -o tsv)
ACR_PASS=$(az acr credential show -n $ACR_NAME --query "passwords[0].value" -o tsv)

az container create \
  --resource-group $RG \
  --name webapp-aci \
  --image $ACR_SERVER/$IMAGE:$TAG \
  --registry-login-server $ACR_SERVER \
  --registry-username $ACR_USER \
  --registry-password $ACR_PASS \
  --os-type Linux --cpu 1 --memory 1 \
  --ports 80 \
  --dns-name-label webapp-$RANDOM

az container show -g $RG -n webapp-aci --query ipAddress.fqdn -o tsv
```
Open the FQDN in a browser. (For production, prefer a managed identity over the admin user.)

---

## 🛠️ Troubleshooting

| Problem | Fix |
|---------|-----|
| `unauthorized: authentication required` on push | Run `az acr login --name $ACR_NAME` again (token expires after ~3 hours). |
| `The registry name is invalid / already in use` | ACR names are global — pick another, lowercase letters and numbers only. |
| `port is already allocated` | Something is using 8080: `docker rm -f $IMAGE` or use `-p 8081:80`. |
| `exec format error` on Azure | Image was built on ARM — rebuild with `--platform linux/amd64`. |
| `az acr login` fails: Docker not running | Start Docker Desktop first. |

---

## 🧹 Clean up

```bash
docker rm -f $IMAGE webapp-acr 2>/dev/null
docker rmi $IMAGE:$TAG $ACR_SERVER/$IMAGE:$TAG $ACR_SERVER/$IMAGE:latest
az group delete --name $RG --yes --no-wait     # deletes the ACR and everything in the group
```

---

## 📋 Command cheat sheet

```bash
docker build -t webappdeployment:v1 .
az login
az group create -n rg-webappdemo -l centralindia
az acr create -g rg-webappdemo -n <acrname> --sku Basic
az acr login -n <acrname>
docker tag  webappdeployment:v1 <acrname>.azurecr.io/webappdeployment:v1
docker push <acrname>.azurecr.io/webappdeployment:v1
az acr repository show-tags -n <acrname> --repository webappdeployment -o table
```
