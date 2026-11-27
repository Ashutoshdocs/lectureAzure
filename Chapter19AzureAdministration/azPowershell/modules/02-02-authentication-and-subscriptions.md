# Module 02 – Authenticate to Azure and Select a Subscription

## Objective
Sign in interactively, inspect the current context, switch subscriptions, and understand service-principal and managed-identity authentication.

## 1. Interactive login
```powershell
Connect-AzAccount
```

For a specific tenant:
```powershell
Connect-AzAccount -Tenant "<TENANT_ID>"
```

## 2. List subscriptions
```powershell
Get-AzSubscription | Format-Table Name, Id, TenantId, State
```

## 3. Select subscription
```powershell
Set-AzContext -Subscription "<SUBSCRIPTION_ID>"
Get-AzContext
```

## 4. Sign out
```powershell
Disconnect-AzAccount
```

## 5. Service principal authentication (lab pattern)
Prefer certificate-based authentication or workload identity federation for automation. If a client secret is required for a temporary lab, retrieve it from a secure secret store rather than hard-coding it.
```powershell
$tenantId = "<TENANT_ID>"
$appId = "<APPLICATION_CLIENT_ID>"
$secret = Read-Host "Enter service principal secret" -AsSecureString
$credential = [pscredential]::new($appId, $secret)
Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $credential
```

## 6. Managed identity authentication (run on an Azure resource with identity enabled)
System-assigned identity:
```powershell
Connect-AzAccount -Identity
```

User-assigned identity:
```powershell
Connect-AzAccount -Identity -AccountId "<MANAGED_IDENTITY_CLIENT_ID>"
```

The identity must have the required Azure RBAC permissions. Authentication does not automatically grant access.

## Teaching points
- `Connect-AzAccount` authenticates the operator or workload.
- `Get-AzContext` shows the active account, tenant, and subscription.
- `Set-AzContext` changes the active subscription context.
- Managed identity avoids storing credentials on supported Azure hosts.
- Use least privilege and scope role assignments narrowly.

## Lab task
Sign in, list subscriptions, select one, inspect context, and sign out.

## Official reference
https://learn.microsoft.com/powershell/azure/authenticate-azureps
