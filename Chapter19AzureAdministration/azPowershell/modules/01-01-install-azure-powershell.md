# Module 01 – Install Azure PowerShell

## Objective
Install the Az PowerShell module on Windows PowerShell 7 / Windows PowerShell, verify the installation, and understand how Az modules are organized.

## Recommended environment
Use **PowerShell 7** where possible. Run PowerShell as your normal user unless your organization's installation policy requires an elevated session.

## 1. Check PowerShell version
```powershell
$PSVersionTable
```

## 2. Install the Az module
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Install-Module -Name Az -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
```

If PowerShell asks whether to trust PSGallery, review the prompt and confirm according to your organization's policy.

## 3. Update Az
```powershell
Update-Module -Name Az
```

Close and reopen PowerShell after installing/updating modules if commands are not recognized.

## 4. Verify
```powershell
Get-InstalledModule -Name Az
Get-Module -Name Az -ListAvailable
Get-Command -Module Az.Accounts | Select-Object -First 10
Get-AzContext
```

## 5. Install only a specific Az module (optional)
Az is a rollup module. You can install individual modules when you want a smaller footprint:
```powershell
Install-Module Az.Accounts -Scope CurrentUser -Repository PSGallery
Install-Module Az.Resources -Scope CurrentUser -Repository PSGallery
Install-Module Az.Compute -Scope CurrentUser -Repository PSGallery
Install-Module Az.Network -Scope CurrentUser -Repository PSGallery
Install-Module Az.Storage -Scope CurrentUser -Repository PSGallery
```

## Teaching points
- `Az` is the modern Azure PowerShell module family.
- `AzureRM` is the legacy module family; do not mix AzureRM and Az in the same session.
- PowerShell cmdlets generally use Verb-Noun naming, such as `Get-AzResourceGroup`.
- `Get-Help Get-AzVM -Examples` is useful for learning a cmdlet.

## Lab task
Install Az, verify the module version, and find the commands available in `Az.Compute`.

## Official reference
https://learn.microsoft.com/powershell/azure/install-azure-powershell
