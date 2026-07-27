# =============================================================================
# deploy-infra.ps1  (complete, re-runnable)
# Creates ALL Azure infrastructure for the data-webapp project:
#   Resource group, ACR, PostgreSQL Flexible Server + DB, App Service plan,
#   Web App for Containers (wired to ACR + DB), and a GitHub service principal.
#
# Safe to run more than once: existing resources are detected and skipped.
# Works on Windows PowerShell 5.1 and PowerShell 7.
#
# Prerequisites:
#   az --version           (Azure CLI installed)
#   az login               (signed in)
#   az account set --subscription "<name-or-id>"
#
# Run:  pwsh ./infra/deploy-infra.ps1      (or)   powershell -File .\deploy-infra.ps1
# =============================================================================
cls
$ErrorActionPreference = "Stop"
# Stop PowerShell from treating Azure CLI's stderr warnings as fatal errors.
$PSNativeCommandUseErrorActionPreference = $false
$env:AZURE_CORE_ONLY_SHOW_ERRORS = "true"

# ---- Settings ---------------------------------------------------------------
$location  = "centralus"
$rg        = "rg-datawebapp"
$pgAdmin   = "appadmin"
$dbName    = "appdb"
$imageName = "data-webapp"                 # must match IMAGE_NAME in the workflow
$pgPass    = "Azure@123456789Ab"           # DB admin password (change if you like)

# Remember a stable suffix across runs so names don't change on re-run.
$stateFile = Join-Path $PSScriptRoot ".suffix"
if (Test-Path $stateFile) {
  $suffix = (Get-Content $stateFile -Raw).Trim()
} else {
  $suffix = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
  $suffix | Out-File -FilePath $stateFile -Encoding ascii -NoNewline
}

$acrName    = "acrdatawebapp$suffix"
$planName   = "plan-datawebapp"
$webappName = "app-datawebapp-$suffix"
$pgName     = "pg-datawebapp-$suffix"

Write-Host ""
Write-Host "Infrastructure suffix $suffix  region $location" -ForegroundColor Cyan
Write-Host ""

# Small helper: returns $true if an 'az ... show' succeeds.
function Test-AzExists([string]$cmd) {
  try { Invoke-Expression "$cmd 2>`$null" | Out-Null; return ($LASTEXITCODE -eq 0) }
  catch { return $false }
}

# ---- 1. Resource group ------------------------------------------------------
Write-Host "1/7  Resource group ($rg)..." -ForegroundColor Yellow
az group create --name $rg --location $location --output none

# ---- 2. Container registry --------------------------------------------------
Write-Host "2/7  Container registry ($acrName)..." -ForegroundColor Yellow
if (-not (Test-AzExists "az acr show --name $acrName")) {
  az acr create --resource-group $rg --name $acrName --sku Basic --admin-enabled true --output none
} else { Write-Host "     already exists, skipping." -ForegroundColor DarkGray }

$acrLoginServer = az acr show --name $acrName --query loginServer -o tsv
$acrUser        = az acr credential show --name $acrName --query username -o tsv
$acrPass        = az acr credential show --name $acrName --query "passwords[0].value" -o tsv
$acrId          = az acr show --name $acrName --query id -o tsv

# ---- 3. PostgreSQL Flexible Server + database -------------------------------
Write-Host "3/7  PostgreSQL server ($pgName)... (first time takes a few minutes)" -ForegroundColor Yellow
if (-not (Test-AzExists "az postgres flexible-server show --resource-group $rg --name $pgName")) {
  az postgres flexible-server create `
    --resource-group $rg --name $pgName --location $location `
    --admin-user $pgAdmin --admin-password $pgPass `
    --tier Burstable --sku-name Standard_B1ms --version 16 `
    --storage-size 32 --public-access 0.0.0.0 --yes --output none
} else {
  Write-Host "     already exists; ensuring the admin password matches." -ForegroundColor DarkGray
  az postgres flexible-server update --resource-group $rg --name $pgName --admin-password $pgPass --output none
}

Write-Host "     Ensuring database ($dbName)..." -ForegroundColor Yellow
az postgres flexible-server db create --resource-group $rg --server-name $pgName --database-name $dbName --output none

$pgHost      = "$pgName.postgres.database.azure.com"
$databaseUrl = "postgresql://$($pgAdmin):$($pgPass)@$($pgHost):5432/$($dbName)?sslmode=require"

# ---- 4. App Service plan (Linux) --------------------------------------------
Write-Host "4/7  App Service plan ($planName)..." -ForegroundColor Yellow
if (-not (Test-AzExists "az appservice plan show --resource-group $rg --name $planName")) {
  az appservice plan create --resource-group $rg --name $planName --is-linux --sku B1 --location $location --output none
} else { Write-Host "     already exists, skipping." -ForegroundColor DarkGray }

# ---- 5. Web App for Containers ----------------------------------------------
Write-Host "5/7  Web App ($webappName)..." -ForegroundColor Yellow
if (-not (Test-AzExists "az webapp show --resource-group $rg --name $webappName")) {
  az webapp create --resource-group $rg --plan $planName --name $webappName `
    --deployment-container-image-name "mcr.microsoft.com/appsvc/staticsite:latest" --output none
} else { Write-Host "     already exists, updating settings." -ForegroundColor DarkGray }

# Point the app at ACR (admin creds) — always refresh this.
az webapp config container set `
  --resource-group $rg --name $webappName `
  --container-image-name "$acrLoginServer/$($imageName):latest" `
  --container-registry-url "https://$acrLoginServer" `
  --container-registry-user $acrUser `
  --container-registry-password $acrPass `
  --output none

# App settings: container port + DB connection — always refresh these.
az webapp config appsettings set `
  --resource-group $rg --name $webappName `
  --settings WEBSITES_PORT=3000 PGSSL=true "DATABASE_URL=$databaseUrl" `
  --output none

# ---- 6. Service principal for GitHub Actions --------------------------------
Write-Host "6/7  Service principal for GitHub..." -ForegroundColor Yellow
$subId = az account show --query id -o tsv
$rgId  = "/subscriptions/$subId/resourceGroups/$rg"

$azureCredentials = az ad sp create-for-rbac `
  --name "gh-$webappName" --role contributor --scopes $rgId --sdk-auth

$clientId = ($azureCredentials | ConvertFrom-Json).clientId

# ---- 7. Let the SP push to ACR ---------------------------------------------
Write-Host "7/7  Granting AcrPush to the service principal..." -ForegroundColor Yellow
az role assignment create --assignee $clientId --scope $acrId --role AcrPush --output none 2>$null

# ---- Output -----------------------------------------------------------------
Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host " Infrastructure is ready." -ForegroundColor Green
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "App URL (live after the first pipeline run):" -ForegroundColor Cyan
Write-Host "  https://$webappName.azurewebsites.net"
Write-Host ""
Write-Host "Add these as GitHub repository secrets" -ForegroundColor Cyan
Write-Host "(Repo -> Settings -> Secrets and variables -> Actions -> New secret):"
Write-Host ""
Write-Host "  ACR_NAME          = $acrName"
Write-Host "  ACR_LOGIN_SERVER  = $acrLoginServer"
Write-Host "  WEBAPP_NAME       = $webappName"
Write-Host ""
Write-Host "  AZURE_CREDENTIALS = (the full JSON block below, copy all of it)"
Write-Host "-----------------------------------------------------------------------"
Write-Host $azureCredentials
Write-Host "-----------------------------------------------------------------------"
Write-Host ""
Write-Host "DATABASE_URL (already set on the Web App):" -ForegroundColor Cyan
Write-Host "  $databaseUrl"
Write-Host ""

# Save the same values locally (this file is gitignored).
@"
ACR_NAME=$acrName
ACR_LOGIN_SERVER=$acrLoginServer
WEBAPP_NAME=$webappName
APP_URL=https://$webappName.azurewebsites.net
DATABASE_URL=$databaseUrl

AZURE_CREDENTIALS:
$azureCredentials
"@ | Out-File -FilePath (Join-Path $PSScriptRoot "github-secrets.txt") -Encoding utf8

Write-Host "A copy was written to infra/github-secrets.txt (do not commit it)." -ForegroundColor DarkGray
