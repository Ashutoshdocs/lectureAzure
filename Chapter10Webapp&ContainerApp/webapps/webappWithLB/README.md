# ⚖️ webappWithLB — Azure App Service Scale-Out & Load Balancing Demo

A small Node.js/Express app, packaged with Docker, pushed to **Azure Container Registry (ACR)** and run on **Azure App Service (Linux)** with several instances behind App Service's built-in load balancer.

Each instance paints itself in its **own colour gradient** and shows its ID, so every refresh visibly proves which instance served you. The page also has a **Load balancer test** panel that fires 20–100 requests and draws a live bar chart of how they were spread.

```
          ┌──────────────┐
 Users ──▶│ App Service  │──▶ Instance A  (purple)
          │ front end /  │──▶ Instance B  (teal)
          │ load balancer│──▶ Instance C  (coral)
          └──────────────┘
                 ▲ pulls image
          ┌──────────────┐
          │     ACR      │  scaledemo:v1
          └──────────────┘
```

---

## 📁 Project files

| File | Purpose |
|------|---------|
| `server.js` | Express app: demo page + API endpoints |
| `package.json` | Dependencies (Express) |
| `Dockerfile` | `node:20-alpine`, non-root user, health check |
| `.dockerignore` | Keeps the image small |
| `deploy.ps1` | One-shot: build → ACR → App Service → scale out |
| `test-lb.ps1` | Sends N requests and prints the distribution per instance |

### Endpoints

| Path | Returns |
|------|---------|
| `/` | Demo page (instance colour, details, LB test panel) |
| `/api/info` (or `/info`) | JSON: instance, hostname, region, SKU, hits, uptime |
| `/instance` | Plain text short instance ID |
| `/hostname` | Plain text container hostname |
| `/health` | `OK`, used by App Service health check |

---

## ✅ Prerequisites

- Docker Desktop (running)
- Azure CLI → `az --version` and `az login`
- PowerShell (Windows PowerShell 5.1 or PowerShell 7)

---

## 1️⃣ Run locally

```powershell
docker build -t scaledemo:v1 .
docker run -d --name scaledemo -p 8080:8080 scaledemo:v1
```

Open **http://localhost:8080**

```powershell
curl http://localhost:8080/instance
curl http://localhost:8080/api/info
curl http://localhost:8080/health
```

> Locally there's only one container, so the LB test shows one bar. That's expected.

Stop it: `docker rm -f scaledemo`

---

## 🚀 Quick path: deploy everything with one script

Edit the top of `deploy.ps1` (`$ACR` and `$APP` must be globally unique), then:

```powershell
.\deploy.ps1
.\test-lb.ps1 -App scaledemo123456 -Count 30
```

The manual steps below do exactly what the script does, for when you want to demo each stage.

---

## 2️⃣ Variables

```powershell
$RG       = "RG-WebApp"
$LOCATION = "centralus"
$ACR      = "myacrdemoblaze"      # globally unique, lowercase + numbers
$PLAN     = "ScalePlan"
$APP      = "scaledemo123456"     # globally unique
$IMAGE    = "scaledemo"
$TAG      = "v1"
```

## 3️⃣ Create resource group and ACR

```powershell
az group create --name $RG --location $LOCATION
az acr create --name $ACR --resource-group $RG --sku Basic --admin-enabled true
```

## 4️⃣ Build, tag, push

```powershell
docker build --platform linux/amd64 -t "${IMAGE}:$TAG" .

az acr login -n $ACR
docker tag "${IMAGE}:$TAG" "$ACR.azurecr.io/${IMAGE}:$TAG"
docker push "$ACR.azurecr.io/${IMAGE}:$TAG"

az acr repository show-tags -n $ACR --repository $IMAGE -o table
```

> `--platform linux/amd64` matters on Apple Silicon; App Service runs amd64.

## 5️⃣ Create the App Service plan and Web App

```powershell
az appservice plan create -g $RG -n $PLAN --sku P1v3 --is-linux

az webapp create -g $RG -p $PLAN -n $APP --container-image-name "$ACR.azurecr.io/${IMAGE}:$TAG"
```

## 6️⃣ Let the Web App pull from ACR

```powershell
$ACR_USER = az acr credential show -n $ACR --query username -o tsv
$ACR_PASS = az acr credential show -n $ACR --query "passwords[0].value" -o tsv

az webapp config container set -g $RG -n $APP `
  --container-image-name "$ACR.azurecr.io/${IMAGE}:$TAG" `
  --container-registry-url "https://$ACR.azurecr.io" `
  --container-registry-user $ACR_USER `
  --container-registry-password $ACR_PASS
```

## 7️⃣ Configure port, health check, and turn off ARR affinity

```powershell
# Container listens on 8080
az webapp config appsettings set -g $RG -n $APP --settings WEBSITES_PORT=8080 APP_VERSION=$TAG

# App Service stops routing to an instance that fails /health
az webapp config set -g $RG -n $APP --generic-configurations '{\"healthCheckPath\":\"/health\"}'

# Turn off sticky sessions so requests are spread across instances
az webapp update -g $RG -n $APP --set clientAffinityEnabled=false
az webapp show -g $RG -n $APP --query clientAffinityEnabled     # → false

az webapp restart -g $RG -n $APP
```

Open `https://$APP.azurewebsites.net` — with one instance, every refresh shows the **same** colour and ID.

---

## 8️⃣ Scale out and watch the load balancer

```powershell
az appservice plan update -g $RG -n $PLAN --number-of-workers 3
az appservice plan show -g $RG -n $PLAN --query sku.capacity     # → 3
```

Wait 1–2 minutes for the new instances to start, then demo it three ways:

1. **Refresh the browser** — the colour and instance ID change between instances.
2. **Click "Run test"** on the page — the bar chart shows requests split across 3 instances.
3. **From PowerShell:**

```powershell
.\test-lb.ps1 -App $APP -Count 30
```

Example output:

```
Distribution:
Instance  Count Share Bar
--------  ----- ----- ---
3F9A12BC     11 37 %  ###########
A07D44E1     10 33 %  ##########
C51B9D02      9 30 %  #########

Load balancing works: 3 instances answered.
```

### 🔁 Show what ARR affinity does (optional)

```powershell
az webapp update -g $RG -n $APP --set clientAffinityEnabled=true
```

Now the browser always lands on the same instance (it gets an `ARRAffinity` cookie). Switch it back to `false` afterwards.

### Scale back in

```powershell
az appservice plan update -g $RG -n $PLAN --number-of-workers 1
```

---

## 📈 Optional: autoscale on CPU

Needs Standard (S1) or Premium (P1v3) tier.

```powershell
$PLAN_ID = az appservice plan show -g $RG -n $PLAN --query id -o tsv

az monitor autoscale create -g $RG --resource $PLAN_ID `
  --name "$PLAN-autoscale" --min-count 1 --max-count 5 --count 2

az monitor autoscale rule create -g $RG --autoscale-name "$PLAN-autoscale" `
  --condition "CpuPercentage > 70 avg 5m" --scale out 1

az monitor autoscale rule create -g $RG --autoscale-name "$PLAN-autoscale" `
  --condition "CpuPercentage < 30 avg 10m" --scale in 1
```

---

## 🔄 Release v2

Change something visible (e.g. the subtitle in `server.js`), then:

```powershell
$TAG = "v2"
docker build --platform linux/amd64 -t "${IMAGE}:$TAG" .
docker tag "${IMAGE}:$TAG" "$ACR.azurecr.io/${IMAGE}:$TAG"
docker push "$ACR.azurecr.io/${IMAGE}:$TAG"

az webapp config container set -g $RG -n $APP --container-image-name "$ACR.azurecr.io/${IMAGE}:$TAG"
az webapp config appsettings set -g $RG -n $APP --settings APP_VERSION=$TAG
```

All instances roll to v2; the badge on the page shows the new version.

---

## 🔐 Better for production: managed identity instead of admin password

```powershell
az webapp identity assign -g $RG -n $APP
$PRINCIPAL = az webapp identity show -g $RG -n $APP --query principalId -o tsv
$ACR_ID    = az acr show -n $ACR --query id -o tsv

az role assignment create --assignee $PRINCIPAL --role AcrPull --scope $ACR_ID
az resource update -g $RG --name $APP --resource-type "Microsoft.Web/sites/config" `
  --namespace Microsoft.Web --parent "sites/$APP" -n web `
  --set properties.acrUseManagedIdentityCreds=true

az acr update -n $ACR --admin-enabled false
```

---

## 🛠️ Troubleshooting

| Symptom | Fix |
|---------|-----|
| Site shows *Application Error* / container won't start | Check `WEBSITES_PORT=8080` is set. View logs: `az webapp log tail -g $RG -n $APP` |
| *ImagePullFailure* in logs | Registry credentials missing or wrong: rerun step 6. |
| Always the same instance | Instance count still 1, or `clientAffinityEnabled` is `true`, or the new instances are still warming up. |
| `exec format error` | Image built for ARM. Rebuild with `--platform linux/amd64`. |
| Push says `unauthorized` | `az acr login -n $ACR` again (token lasts ~3 hours). |
| ACR/App name rejected | Names are global; choose a different one. |

---

## 💰 Cost note & cleanup

P1v3 × 3 instances is billed per hour. B1 is cheaper and supports manual scale-out up to 3 instances (no autoscale). Delete everything when done:

```powershell
az group delete --name $RG --yes --no-wait
docker rm -f scaledemo
docker rmi scaledemo:v1
```
