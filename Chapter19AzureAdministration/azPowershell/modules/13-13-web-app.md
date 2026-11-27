# Module 13 – Deploy an Azure Web App using Azure PowerShell

## Objective
Create an App Service plan and Linux Web App, configure an app setting, and inspect the application.

## 1. Variables
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$Plan = "plan-azps-demo"
$WebApp = "webazps$((New-Guid).ToString('N').Substring(0,8))"
```

## 2. Create Linux App Service plan
```powershell
New-AzAppServicePlan -Name $Plan -ResourceGroupName $RG -Location $Location -Tier Basic -NumberofWorkers 1 -WorkerSize Small -Linux
```

## 3. Create Web App
```powershell
New-AzWebApp -Name $WebApp -ResourceGroupName $RG -Location $Location -AppServicePlan $Plan
```

Runtime configuration capabilities vary by Az.Websites version and App Service platform support. Use `Get-Help Set-AzWebApp -Examples` and the current App Service runtime stack documentation to configure a supported runtime.

## 4. Configure app settings
```powershell
$Settings = @{ ENVIRONMENT = "Training"; COURSE = "AzurePowerShell" }
Set-AzWebApp -ResourceGroupName $RG -Name $WebApp -AppSettings $Settings
```

## 5. Inspect
```powershell
Get-AzWebApp -ResourceGroupName $RG -Name $WebApp | Format-List Name, State, DefaultHostName, ServerFarmId
```

Open:
```powershell
Start-Process "https://$WebApp.azurewebsites.net"
```

## Teaching points
- App Service plan defines the compute tier and pricing.
- Web App is the hosted application resource.
- The plan can host multiple apps, subject to plan limits.
- A Web App is not the same service as Azure Container Instances or AKS.

## Lab task
Create a Web App, add an app setting, open its URL, and inspect the configuration.
