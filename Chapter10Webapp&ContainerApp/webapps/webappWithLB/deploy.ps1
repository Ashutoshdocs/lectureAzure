# =====================================================================
#  webappWithLB - build, push to ACR, deploy to App Service, scale out
#  Run from the project folder in PowerShell:  .\deploy.ps1
# =====================================================================

# ---- Settings (change ACR and APP: they must be globally unique) ----
$RG       = "RG-WebApp"
$LOCATION = "centralus"
$ACR      = "myacrdemoblaze"        # lowercase letters/numbers, 5-50 chars
$PLAN     = "ScalePlan"
$APP      = "scaledemo123456"       # becomes https://$APP.azurewebsites.net
$IMAGE    = "scaledemo"
$TAG      = "v1"
$SKU      = "P1v3"                  # B1 works too (manual scale, max 3 instances)
$WORKERS  = 3

$ErrorActionPreference = "Stop"
$ACR_SERVER = "$ACR.azurecr.io"
$FULL_IMAGE = "$ACR_SERVER/${IMAGE}:$TAG"

Write-Host "`n[1/8] Building image $IMAGE`:$TAG" -ForegroundColor Cyan
docker build --platform linux/amd64 -t "${IMAGE}:$TAG" .

Write-Host "`n[2/8] Resource group + ACR" -ForegroundColor Cyan
az group create --name $RG --location $LOCATION -o none
az acr create --name $ACR --resource-group $RG --sku Basic --admin-enabled true -o none

Write-Host "`n[3/8] Tag + push to $ACR_SERVER" -ForegroundColor Cyan
az acr login -n $ACR
docker tag "${IMAGE}:$TAG" $FULL_IMAGE
docker push $FULL_IMAGE
az acr repository show-tags -n $ACR --repository $IMAGE -o table

Write-Host "`n[4/8] App Service plan ($SKU, Linux)" -ForegroundColor Cyan
az appservice plan create -g $RG -n $PLAN --sku $SKU --is-linux -o none

Write-Host "`n[5/8] Web App from ACR image" -ForegroundColor Cyan
$ACR_USER = az acr credential show -n $ACR --query username -o tsv
$ACR_PASS = az acr credential show -n $ACR --query "passwords[0].value" -o tsv

az webapp create -g $RG -p $PLAN -n $APP --container-image-name $FULL_IMAGE -o none
az webapp config container set -g $RG -n $APP `
  --container-image-name $FULL_IMAGE `
  --container-registry-url "https://$ACR_SERVER" `
  --container-registry-user $ACR_USER `
  --container-registry-password $ACR_PASS -o none

Write-Host "`n[6/8] App settings, health check, ARR affinity off" -ForegroundColor Cyan
# The container listens on 8080; App Service needs to be told
az webapp config appsettings set -g $RG -n $APP --settings WEBSITES_PORT=8080 APP_VERSION=$TAG -o none
az webapp config set -g $RG -n $APP --generic-configurations '{\"healthCheckPath\":\"/health\"}' -o none
# Without this, the LB pins each browser to one instance with a cookie
az webapp update -g $RG -n $APP --set clientAffinityEnabled=false -o none

Write-Host "`n[7/8] Scale out to $WORKERS instances" -ForegroundColor Cyan
az appservice plan update -g $RG -n $PLAN --number-of-workers $WORKERS -o none
az webapp restart -g $RG -n $APP

Write-Host "`n[8/8] Done" -ForegroundColor Green
Write-Host "URL:            https://$APP.azurewebsites.net"
Write-Host "ARR affinity:   $(az webapp show -g $RG -n $APP --query clientAffinityEnabled -o tsv)"
Write-Host "Instances:      $(az appservice plan show -g $RG -n $PLAN --query sku.capacity -o tsv)"
Write-Host "`nGive it 1-2 minutes to pull the image, then run .\test-lb.ps1"
