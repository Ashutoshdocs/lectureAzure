# Module 05 – Create and Manage a Storage Account and Blob Container

## Objective
Create a StorageV2 account, create a private blob container, upload a file, and inspect the result.

## 1. Set variables
Storage Account names must be globally unique, lowercase, 3–24 characters.
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$StorageName = "stazps$((New-Guid).ToString('N').Substring(0,8))"
```

## 2. Create resource group and Storage Account
```powershell
New-AzResourceGroup -Name $RG -Location $Location
$Storage = New-AzStorageAccount -ResourceGroupName $RG -Name $StorageName -Location $Location -SkuName Standard_LRS -Kind StorageV2 -AccessTier Hot -MinimumTlsVersion TLS1_2
```

## 3. Create container using Microsoft Entra authorization
The signed-in identity needs an appropriate data-plane role such as Storage Blob Data Contributor.
```powershell
$Context = New-AzStorageContext -StorageAccountName $StorageName -UseConnectedAccount
New-AzStorageContainer -Name "training-data" -Context $Context -Permission Off
```

## 4. Upload and list blobs
```powershell
"Azure PowerShell Blob demo" | Set-Content .\demo.txt
Set-AzStorageBlobContent -File .\demo.txt -Container "training-data" -Blob "demo.txt" -Context $Context -Force
Get-AzStorageBlob -Container "training-data" -Context $Context | Select-Object Name, Length
```

## 5. Download
```powershell
Get-AzStorageBlobContent -Container "training-data" -Blob "demo.txt" -Destination ".\downloaded-demo.txt" -Context $Context -Force
```

## Teaching points
- `New-AzStorageAccount` creates the management-plane resource.
- `New-AzStorageContext -UseConnectedAccount` uses the current Entra identity for data operations.
- Azure RBAC management permissions and blob data permissions are different.
- Keep public container access disabled unless there is a reviewed requirement.

## Lab task
Create another private container, upload a second file, list blobs, and download one blob.
