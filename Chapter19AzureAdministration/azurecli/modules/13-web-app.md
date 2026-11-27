# Module 13 – Deploy an Azure Web App using Azure CLI

## Objective
Create an App Service plan and Web App, deploy a simple sample, and inspect the app.

Bash:
```bash
RG="rg-azcli-training"
LOCATION="centralindia"
PLAN="plan-azcli-demo"
WEBAPP="webazcli$(openssl rand -hex 4)"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$LOCATION = "centralindia"
$PLAN = "plan-azcli-demo"
$WEBAPP = "webazcli$((New-Guid).ToString('N').Substring(0,8))"
```

## 1. Create App Service plan
```bash
az appservice plan create \
  --name "$PLAN" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku B1 \
  --is-linux
```

## 2. Create Web App (Python runtime example)
```bash
az webapp create \
  --resource-group "$RG" \
  --plan "$PLAN" \
  --name "$WEBAPP" \
  --runtime "PYTHON:3.12"
```

Runtime availability changes over time. If this runtime is not accepted, inspect supported runtimes:
```bash
az webapp list-runtimes --os linux --output table
```

## 3. Inspect app
```bash
az webapp show --resource-group "$RG" --name "$WEBAPP" --output table
az webapp browse --resource-group "$RG" --name "$WEBAPP"
```

## 4. Configure app settings
```bash
az webapp config appsettings set \
  --resource-group "$RG" \
  --name "$WEBAPP" \
  --settings ENVIRONMENT=Training
```

## 5. View logs
```bash
az webapp log config --resource-group "$RG" --name "$WEBAPP" --application-logging filesystem
az webapp log tail --resource-group "$RG" --name "$WEBAPP"
```

## Teaching points
- App Service plan defines compute resources and pricing tier.
- Web App is the hosted application resource.
- The plan can host multiple apps subject to plan limits.
- A Web App is not the same service as Azure Container Instances or Azure Kubernetes Service.

## Lab task
Create a Web App with a unique name, add an app setting, open its URL, and inspect its configuration.
