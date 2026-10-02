# Deploy dotnet10-webapp-demo to Azure App Service (Linux, .NET 10) from Windows PowerShell.
#
# Usage (run from this folder):
#   .\deploy.ps1                                  # new app with a random name
#   .\deploy.ps1 -App blazecheck -ResourceGroup test   # deploy to an existing app
#
# If scripts are blocked:  Set-ExecutionPolicy -Scope Process Bypass

param(
    [string]$ResourceGroup = "rg-dotnet10-demo",
    [string]$Location      = "centralindia",
    [string]$Plan          = "plan-dotnet10-demo",
    [string]$App           = "dotnet10-demo-$(Get-Random -Maximum 99999)",
    [string]$Sku           = "B1",
    [string]$Runtime       = "DOTNETCORE:10.0"
)

$ErrorActionPreference = "Stop"
$Dll = "Dotnet10WebappDemo.dll"
Set-Location $PSScriptRoot

function Run-Az {
    # Runs an az command and stops the script if it fails.
    & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args[0..1] -join ' ') failed (exit $LASTEXITCODE)" }
}

# --- 1. Build ---------------------------------------------------------------
Write-Host "==> Building (dotnet publish)" -ForegroundColor Cyan
Remove-Item -Recurse -Force publish, app.zip -ErrorAction SilentlyContinue
dotnet publish -c Release -o publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

# --- 2. Zip the CONTENTS of publish (DLL at the zip root, forward-slash paths) ---
Write-Host "==> Creating app.zip" -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Join-Path $PSScriptRoot "publish"), (Join-Path $PSScriptRoot "app.zip"))

# --- 3. Create resources only if the app doesn't exist yet -------------------
$existing = az webapp list --query "[?name=='$App'].name" -o tsv
if (-not $existing) {
    Write-Host "==> Resource group: $ResourceGroup ($Location)" -ForegroundColor Cyan
    Run-Az group create --name $ResourceGroup --location $Location --output none

    Write-Host "==> App Service plan: $Plan ($Sku, Linux)" -ForegroundColor Cyan
    Run-Az appservice plan create --name $Plan --resource-group $ResourceGroup --sku $Sku --is-linux --output none

    Write-Host "==> Web app: $App ($Runtime)" -ForegroundColor Cyan
    Run-Az webapp create --name $App --resource-group $ResourceGroup --plan $Plan --runtime $Runtime --output none
} else {
    Write-Host "==> Using existing web app: $App" -ForegroundColor Cyan
}

# --- 4. Make sure runtime + startup command match this app -------------------
# (A wrong runtime or startup command is what causes endless "Starting the site...")
Write-Host "==> Setting runtime DOTNETCORE|10.0, startup command and health check" -ForegroundColor Cyan
Run-Az webapp config set --name $App --resource-group $ResourceGroup `
    --linux-fx-version "DOTNETCORE|10.0" `
    --startup-file "dotnet $Dll" `
    --generic-configurations '{\"healthCheckPath\": \"/api/health\"}' --output none

Run-Az webapp log config --name $App --resource-group $ResourceGroup `
    --docker-container-logging filesystem --output none

# --- 5. Deploy ----------------------------------------------------------------
Write-Host "==> Deploying app.zip" -ForegroundColor Cyan
Run-Az webapp deploy --name $App --resource-group $ResourceGroup --src-path app.zip --type zip

$hostName = az webapp show --name $App --resource-group $ResourceGroup --query defaultHostName -o tsv
Write-Host ""
Write-Host "Deployed: https://$hostName" -ForegroundColor Green
Write-Host "Health:   https://$hostName/api/health"
Write-Host "Logs:     az webapp log tail --name $App --resource-group $ResourceGroup"
Write-Host "Cleanup:  az group delete --name $ResourceGroup --yes --no-wait"
