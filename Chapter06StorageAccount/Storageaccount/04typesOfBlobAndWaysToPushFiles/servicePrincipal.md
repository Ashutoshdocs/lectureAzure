# Azure Storage Upload using a Service Principal

Upload a file to Azure Blob Storage using a **Service Principal**, an identity for apps, scripts and CI/CD pipelines (GitHub Actions, Azure DevOps, Jenkins). It works from **anywhere**, including outside Azure. Access is controlled by **Azure RBAC roles**.

## Service Principal vs Managed Identity

| | Service Principal | Managed Identity |
|---|---|---|
| **Works from** | Anywhere: laptops, on-prem servers, CI/CD, other clouds | Only Azure resources (VMs, App Service, Functions, etc.) |
| **Credentials** | Client secret or certificate that **you** manage | None; Azure manages them |
| **Rotation** | Manual; secrets expire | Automatic |
| **Use when** | The code runs outside Azure | The code runs on an Azure resource |

## Prerequisites

- An Azure subscription with a storage account and a container
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed
- Permission to create app registrations in Microsoft Entra ID
- **Owner** or **User Access Administrator** on the target scope, to assign roles

| Resource | Name used in examples |
|---|---|
| Storage Account | `mystg123demo` |
| Container | `demo-container` |
| Service Principal | `sp-storage-demo` |

---

## Setup

### Step 1: Create the Service Principal and Assign a Role
Run this with your own admin account. It creates the service principal and assigns the role in one step. Choose the role from the [table below](#built-in-roles).

Scope to a **single container** (recommended, least privilege):

```bash
az ad sp create-for-rbac \
  --name sp-storage-demo \
  --role "Storage Blob Data Contributor" \
  --scopes "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/mystg123demo/blobServices/default/containers/demo-container"
```

Or scope to the **whole storage account**:

```bash
--scopes "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/mystg123demo"
```

**Output:**

```json
{
  "appId": "<client-id>",
  "displayName": "sp-storage-demo",
  "password": "<client-secret>",
  "tenant": "<tenant-id>"
}
```

> ⚠️ The `password` (client secret) is shown **only once**. Store it right away in a secure place such as Azure Key Vault or your CI/CD secret store.

### Step 2 (Optional): Assign the Role to an Existing Service Principal
If the service principal already exists, assign the role separately:

```bash
az role assignment create \
  --assignee <client-id> \
  --role "Storage Blob Data Contributor" \
  --scope "<container-or-account-scope>"
```

> Role assignments can take up to ~10 minutes to take effect. An `AuthorizationPermissionMismatch` error right after assigning usually just means it hasn't propagated yet.

---

## Upload the File

### Step 3: Sign In as the Service Principal

```bash
az login --service-principal \
  --username <client-id> \
  --password <client-secret> \
  --tenant <tenant-id>
```

> To keep the secret out of shell history, put it in an environment variable first and pass `--password "$AZURE_CLIENT_SECRET"`.

### Step 4: Create a File

```bash
echo "Hello from Service Principal" > file1.txt
```

### Step 5: Upload Using Entra ID Authentication
`--auth-mode login` tells the CLI to use the signed-in service principal instead of an account key.

```bash
az storage blob upload \
  --account-name mystg123demo \
  --container-name demo-container \
  --name file1.txt \
  --file file1.txt \
  --auth-mode login
```

### Step 6: Verify

```bash
az storage blob list \
  --account-name mystg123demo \
  --container-name demo-container \
  --query "[].name" -o table \
  --auth-mode login
```

---

## Using the Service Principal in Applications

Azure SDKs (Python, .NET, Java, JavaScript) pick up these environment variables automatically through `DefaultAzureCredential` / `EnvironmentCredential`:

```bash
export AZURE_CLIENT_ID="<client-id>"
export AZURE_TENANT_ID="<tenant-id>"
export AZURE_CLIENT_SECRET="<client-secret>"
```

---

## Permissions (Minimum Needed)

### Built-in Roles

Pick the **lowest** role that covers what the service principal needs to do:

| Need | Minimum Built-in Role | Read / List | Upload / Overwrite | Delete | Manage ACLs |
|---|---|:-:|:-:|:-:|:-:|
| Read and download only | **Storage Blob Data Reader** | ✅ | ❌ | ❌ | ❌ |
| Upload, read and delete | **Storage Blob Data Contributor** | ✅ | ✅ | ✅ | ❌ |
| Full control, incl. POSIX ACLs (Data Lake Gen2) | **Storage Blob Data Owner** | ✅ | ✅ | ✅ | ✅ |
| Create user delegation SAS tokens | **Storage Blob Delegator** (plus a data role above) | — | — | — | — |

> **Upload-only or no-delete** access has no built-in role; Storage Blob Data Contributor also allows delete. Use a [custom role](#custom-role-upload-only-no-read-no-delete) if the service principal must not read or delete.

### Data Actions per Operation

| Operation | Data Action |
|---|---|
| Download a blob / list blobs | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` |
| Upload or overwrite a blob | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write` |
| Append data (append blobs) / create blobs | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action` |
| Delete a blob | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete` |
| Delete a blob version | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/deleteBlobVersion/action` |
| Read / write blob index tags | `.../blobs/tags/read`, `.../blobs/tags/write` |
| Rename / move (Data Lake Gen2) | `.../blobs/move/action` |
| Generate a user delegation key (for SAS) | `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action` |

### Custom Role: Upload Only (No Read, No Delete)

Save as `blob-uploader-role.json`:

```json
{
  "Name": "Storage Blob Uploader",
  "Description": "Upload blobs only. Cannot read, list or delete.",
  "Actions": [],
  "NotActions": [],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action"
  ],
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/<subscription-id>"]
}
```

Create and assign it:

```bash
az role definition create --role-definition blob-uploader-role.json

az role assignment create \
  --assignee <client-id> \
  --role "Storage Blob Uploader" \
  --scope "<container-or-account-scope>"
```

> With this role, Step 6 (listing blobs) will fail, as expected. Add `blobs/read` to `DataActions` for an **upload + read, no delete** role.

---

## Managing the Secret

The client secret expires (1 year by default). Reset it with:

```bash
az ad sp credential reset --id <client-id>
```

This prints a new `password`; update it everywhere the old one was used.

Delete the service principal when it's no longer needed:

```bash
az ad sp delete --id <client-id>
```

---

## Notes

- **Owner** and **Contributor** on the storage account are management roles: they don't grant data access with `--auth-mode login`. You still need a *Storage Blob Data* role.
- `az ad sp create-for-rbac` without `--role` creates the service principal with **no** role assignment, so always pass `--role` and `--scopes`, or assign one afterward.
- **Scope as narrowly as possible**: a container is narrower than an account, which is narrower than a resource group or subscription.
- **Never commit** the client secret to source control. Use Azure Key Vault, GitHub Secrets or Azure DevOps variable groups.
- Prefer a **certificate** over a client secret for production, or **workload identity federation** (OIDC) for GitHub Actions and Azure DevOps so no secret is needed at all.
- If the code runs on an Azure resource, use a **Managed Identity** instead; there's no secret to manage.
