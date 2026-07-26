# ==========================================
# Azure Web App - Configure App Settings
# ==========================================

# Variables
$RESOURCE_GROUP = "main"
$WEBAPP_NAME    = "webappblazetest"

$DB_HOST     = "blazeserver.postgres.database.azure.com"
$DB_NAME     = "studentdb"
$DB_USER     = "myazureuser@blazeserver"
$DB_PASSWORD = "blaze@123"
$DB_PORT     = "5432"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Configuring Azure Web App Settings..."
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --settings `
        DB_HOST=$DB_HOST `
        DB_NAME=$DB_NAME `
        DB_USER=$DB_USER `
        DB_PASSWORD=$DB_PASSWORD `
        DB_PORT=$DB_PORT `
        WEBSITES_PORT=8000

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Failed to configure application settings." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Application settings configured successfully." -ForegroundColor Green

Write-Host ""
Write-Host "Current Application Settings"
Write-Host "----------------------------"

az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --output table

Write-Host ""
Write-Host "Restarting Web App..." -ForegroundColor Yellow

az webapp restart `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Web App restarted successfully." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "Failed to restart Web App." -ForegroundColor Red
}

Write-Host ""
Write-Host "Configuration Complete." -ForegroundColor Cyan