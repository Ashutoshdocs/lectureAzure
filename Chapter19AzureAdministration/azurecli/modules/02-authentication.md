# Module 02 – Authenticate to Azure: Three Methods

## Objective
Understand the three authentication patterns used in this course:
1. User account (interactive login).
2. Service principal (application/workload identity).
3. Managed identity (Azure-hosted workload identity).

Before starting, install Azure CLI (Module 01).

## Method 1 – User account login

Best for learning, interactive administration, and manual testing.

```bash
az login
```

On Windows, Azure CLI normally uses Web Account Manager; on Linux it normally opens a browser. If browser sign-in is not possible:

```bash
az login --use-device-code
```

Check the signed-in account and subscriptions:

```bash
az account show --output table
az account list --output table
```

Set the intended subscription:

```bash
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
az account show --query "{name:name,id:id,tenantId:tenantId}" --output table
```

Log out:

```bash
az logout
```

**Teaching point:** User sign-in is interactive and supports MFA. Do not automate scripts with a user's password.

## Method 2 – Service principal login

A service principal represents an application identity in Microsoft Entra ID. Use it for non-interactive automation when an appropriate workload identity federation or managed identity is not available.

### Create a lab service principal
Run while signed in as an administrator who is allowed to create role assignments:

```bash
az ad sp create-for-rbac --name "sp-azcli-training" --role Contributor --scopes "/subscriptions/<SUBSCRIPTION_ID>"
```

The command returns values including `appId`, `password`, and `tenant`. Treat the password as a secret: copy it directly into an approved secret store. Do not commit it to a file or Git.

### Sign in using the service principal
Bash:
```bash
read -s -p "Client secret: " SP_SECRET; echo
az login --service-principal \
  --username "<APP_ID>" \
  --password "$SP_SECRET" \
  --tenant "<TENANT_ID>"
unset SP_SECRET
```

PowerShell:
```powershell
$SP_SECRET = Read-Host "Client secret" -AsSecureString
$BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SP_SECRET)
try {
    $PlainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    az login --service-principal --username "<APP_ID>" --password $PlainSecret --tenant "<TENANT_ID>"
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    Remove-Variable PlainSecret -ErrorAction SilentlyContinue
    Remove-Variable SP_SECRET -ErrorAction SilentlyContinue
}
```

For production, prefer federated credentials or certificate-based authentication rather than a long-lived client secret. Never paste a real secret into a shared classroom terminal or recording.

### Verify
```bash
az account show --output table
```

### Remove the lab identity
Only after the exercise, and only if you created this dedicated lab identity:

```bash
az ad sp delete --id "<APP_ID>"
```

## Method 3 – Managed identity login

Managed identity is available to supported Azure resources such as Azure Virtual Machines when an identity is enabled. Azure manages the credentials; the user does not handle a client secret.

### Enable system-assigned identity on a VM
Run from an authenticated administrator session:

```bash
az vm identity assign --resource-group "<RESOURCE_GROUP>" --name "<VM_NAME>"
az vm show --resource-group "<RESOURCE_GROUP>" --name "<VM_NAME>" --query identity
```

### Grant the VM identity access
Get the principal ID:

```bash
PRINCIPAL_ID=$(az vm show -g "<RESOURCE_GROUP>" -n "<VM_NAME>" --query identity.principalId -o tsv)
```

Grant a narrowly scoped role (example: Reader on a resource group):

```bash
SCOPE=$(az group show -n "<RESOURCE_GROUP>" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role Reader --scope "$SCOPE"
```

### Sign in from inside that VM
Connect to the VM, ensure Azure CLI is installed, then:

```bash
az login --identity
az account show --output table
```

For a user-assigned identity, use:

```bash
az login --identity --client-id "<MANAGED_IDENTITY_CLIENT_ID>"
```

**Important:** `az login --identity` must run from an Azure host where that identity is available. It will not work from an ordinary laptop unless the environment provides a managed identity endpoint.

## Comparison

| Method | Who/what signs in? | Best use |
|---|---|---|
| User | Human Entra ID account | Learning and interactive administration |
| Service principal | Application identity | Automation; prefer federation/certificate over secrets |
| Managed identity | Azure resource identity | Workloads running on supported Azure services |

## Lab questions
1. Which method supports an interactive MFA prompt?
2. Why should a pipeline not use a human user's password?
3. Where must `az login --identity` be executed?
4. What is the difference between a service principal and a managed identity?
