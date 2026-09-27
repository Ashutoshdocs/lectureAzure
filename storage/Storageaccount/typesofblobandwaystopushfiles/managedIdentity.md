# Azure Storage Upload using Managed Identity

Upload a file to Azure Blob Storage from an Azure VM (or other Azure resource) using its **Managed Identity**, with no account keys or connection strings. Access is controlled entirely by **Azure RBAC roles**.

## Prerequisites

- An Azure VM (or App Service, Function, container, etc.) with a **Managed Identity** enabled
- A storage account and a container
- Azure CLI installed on the VM
- The identity has a **Storage Blob Data** role on the storage account or container (see [Permissions](#permissions-minimum-needed))

| Resource | Name used in examples |
|---|---|
| Storage Account | `mystg123demo` |
| Container | `demo-container` |

---

## Setup

### Step 1: Enable the Managed Identity on the VM
Skip this if the identity is already on.

```bash
az vm identity assign --name <vm-name> --resource-group <resource-group>
```

Note the `systemAssignedIdentity` value in the output; that's the identity's **principal (object) ID**.

### Step 2: Assign a Role to the Identity
Run this from your own machine with an account that can assign roles (Owner or User Access Administrator). Choose the role from the [table below](#built-in-roles).

Scope to a **single container** (recommended, least privilege):

```bash
az role assignment create \
  --assignee-object-id <principal-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/mystg123demo/blobServices/default/containers/demo-container"
```

Or scope to the **whole storage account**:

```bash
--scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/mystg123demo"
```

> Role assignments can take up to ~10 minutes to take effect. An `AuthorizationPermissionMismatch` error right after assigning usually just means it hasn't propagated yet.

---

## Upload the File

Run these on the VM.

### Step 3: Sign In with the Managed Identity

```bash
az login --identity
```

For a **user-assigned** identity, specify which one:

```bash
az login --identity --client-id <client-id>   # older CLI versions: --username <client-id>
```

### Step 4: Create a File

```bash
echo "Hello from Managed Identity" > file1.txt
```

### Step 5: Upload Using Entra ID Authentication
`--auth-mode login` tells the CLI to use the signed-in identity instead of an account key.

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

## Permissions (Minimum Needed)

### Built-in Roles

Pick the **lowest** role that covers what the identity needs to do:

| Need | Minimum Built-in Role | Read / List | Upload / Overwrite | Delete | Manage ACLs |
|---|---|:-:|:-:|:-:|:-:|
| Read and download only | **Storage Blob Data Reader** | ✅ | ❌ | ❌ | ❌ |
| Upload, read and delete | **Storage Blob Data Contributor** | ✅ | ✅ | ✅ | ❌ |
| Full control, incl. POSIX ACLs (Data Lake Gen2) | **Storage Blob Data Owner** | ✅ | ✅ | ✅ | ✅ |
| Create user delegation SAS tokens | **Storage Blob Delegator** (plus a data role above) | — | — | — | — |

> **Upload-only or no-delete** access has no built-in role; Storage Blob Data Contributor also allows delete. Use a [custom role](#custom-role-upload-only-no-read-no-delete) if the identity must not read or delete.

### Data Actions per Operation

These are the individual permissions behind the roles, useful for building a custom role:

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
  --assignee-object-id <principal-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Uploader" \
  --scope "<container-or-account-scope>"
```

> With this role, Step 6 (listing blobs) will fail, as expected. Add `blobs/read` to `DataActions` for an **upload + read, no delete** role.

---

## Notes

- **Owner** and **Contributor** on the storage account are management roles: they can change settings and read keys, but **don't** grant data access with `--auth-mode login`. You still need a *Storage Blob Data* role.
- **Scope as narrowly as possible**: a container is narrower than an account, which is narrower than a resource group or subscription.
- Managed Identity is more secure than access keys or connection strings: there are no secrets to store, leak or rotate.
- For stricter security, disable key access on the account (**Configuration → Allow storage account key access → Disabled**) so only Entra ID authentication works.
