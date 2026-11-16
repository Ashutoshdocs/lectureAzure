# Azure VM + Storage (Bicep) – dev / psq / prod with Azure DevOps

Deploys, per environment, a **resource group, VNet/subnet/NSG, a VM with a system-assigned managed identity, and a storage account**. It also gives the VM identity the **Storage Blob Data Reader** role on that storage account.
The VM admin **username and password are never stored in the repo**. `passwordgenerator.sh` creates them in a **manually created Key Vault**. The Bicep deployment then reads them from the vault with `getSecret()`.

```
Flow:  passwordgenerator.sh ──► Key Vault (username + password secrets)
                                     │
       Azure DevOps pipeline ──► mainresource.bicep ──getSecret()──┘
                                     ├─ RG
                                     ├─ VNet + subnet + NSG      (modules/vnet.bicep)
                                     ├─ VM + managed identity    (modules/vm.bicep)
                                     ├─ Storage + Blob Data Reader for VM MI (modules/stg.bicep)
                                     └─ Key Vault lookup / optional access   (modules/kv.bicep)
```

## Folder structure

```
azure-bicep-vm-iac/
├── modules/
│   ├── vm.bicep            # NIC (+optional PIP) + VM, SystemAssigned identity
│   ├── stg.bicep           # Storage account, containers, Storage Blob Data Reader role
│   ├── kv.bicep            # EXISTING (manually created) Key Vault – lookup + optional Secrets User role
│   └── vnet.bicep          # NSG + VNet + subnet
├── main/
│   └── mainresource.bicep  # Orchestration (subscription scope) – reads secrets from KV
├── environments/
│   ├── dev/dev.parameters.json
│   ├── psq/psq.parameters.json
│   └── prod/prod.parameters.json
├── pipelines/
│   ├── dev/  dev-whatif.yml   dev-deploy.yml
│   ├── psq/  psq-whatif.yml   psq-deploy.yml
│   └── prod/ prod-whatif.yml  prod-deploy.yml
├── scripts/
│   ├── passwordgenerator.sh   # generates password, stores username+password in Key Vault
│   └── bicep-deploy.sh        # shared what-if / validate / create helper used by pipelines
└── README.md
```

---

## 1. Prerequisites

- An Azure DevOps organization + project with an Azure Repos Git repo (or GitHub).
- Azure subscription(s) for dev / psq / prod. They can be the same subscription.
- Rights to create an App Registration / Managed Identity and assign roles (Owner, or User Access Administrator).
- Locally (only if you generate passwords from your machine): Azure CLI, `jq`, bash.

## 2. Create the Key Vault manually (one time)

You can use one shared vault for all environments, or one vault per environment. The secret names are different per environment either way.

```bash
az login
az account set --subscription <SUBSCRIPTION-ID>

az group create -n rg-shared-kv-cin-001 -l centralindia

az keyvault create \
  --name <KEYVAULT-NAME> \
  --resource-group rg-shared-kv-cin-001 \
  --location centralindia \
  --enable-rbac-authorization true \
  --enabled-for-template-deployment true   # REQUIRED for getSecret() in Bicep
```

If the vault already exists, turn on template deployment:

```bash
az keyvault update -n <KEYVAULT-NAME> --enabled-for-template-deployment true
```

Give yourself rights to write secrets:

```bash
az role assignment create --assignee "<your-UPN-or-objectId>" \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show -n <KEYVAULT-NAME> --query id -o tsv)
```

> The Key Vault must be in the **same subscription** as the environment's `subscriptionId`, because `mainresource.bicep` looks it up with `resourceGroup(subscriptionId, keyVaultResourceGroup)`.

## 3. Fill in the parameter files

Edit `environments/<env>/<env>.parameters.json` for each of dev, psq and prod. Every `<...>` placeholder must be replaced; the pipeline stops if any are left.

| Parameter | What to put |
|---|---|
| `subscriptionId` | **Subscription ID of this environment.** The pipeline switches to this subscription. |
| `keyVaultName` / `keyVaultResourceGroup` | The vault from step 2 |
| `tags.costCenter`, `tags.owner` | Your values |
| `storageAccountName` | Must be **globally unique**: 3–24 characters, lowercase letters and numbers only |
| `resourceGroupName`, `vnetName`, `subnetName`, `vmName`, `vmSize`, CIDRs … | Already different per environment; change them as needed |

Default differences between environments:

| | dev | psq | prod |
|---|---|---|---|
| VM size | Standard_B2s | Standard_D2s_v5 | Standard_D4s_v5 |
| OS disk | StandardSSD 64 GB | StandardSSD 128 GB | Premium 128 GB |
| VNet | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| Storage SKU | LRS | ZRS | GZRS |
| Zone | none | 1 | 1 |

**Windows VM instead of Linux?** Set `"osType": "Windows"` and change the image:

```json
"imageReference": { "value": { "publisher": "MicrosoftWindowsServer", "offer": "WindowsServer", "sku": "2022-datacenter-azure-edition", "version": "latest" } }
```

Optional: `"grantVmKeyVaultSecretsUser": true` also gives the VM identity *Key Vault Secrets User* on the vault. The vault must use RBAC for this.

## 4. Generate the VM password (before the first deployment)

**Option A – from your machine:**

```bash
chmod +x scripts/*.sh
./scripts/passwordgenerator.sh --param-file environments/dev/dev.parameters.json  --username azureadmin
./scripts/passwordgenerator.sh --param-file environments/psq/psq.parameters.json  --username azureadmin
./scripts/passwordgenerator.sh --param-file environments/prod/prod.parameters.json --username azureadmin
```

This creates the secrets `vm-<env>-admin-username` and `vm-<env>-admin-password`. If the password secret already exists, the script leaves it alone. Pass `--force` to rotate it. The password is 24 characters by default (`--length` to change) and is never printed.

**Option B – from the pipeline:** when you run `<env>-deploy.yml`, tick **"Generate VM admin username/password in Key Vault first"**. For this, the service connection's identity needs **Key Vault Secrets Officer** on the vault (see step 5).

To read the password later:

```bash
az keyvault secret show --vault-name <KEYVAULT-NAME> -n vm-dev-admin-password --query value -o tsv
```

> Rotating the secret does **not** change the password on a VM that is already deployed. Reset it on the VM with `az vm user update` if needed.

## 5. Create the service connections in Azure DevOps

Create **one service connection per environment**. The names must match the `serviceConnection` variable in the YAMLs:

| Environment | Service connection name |
|---|---|
| dev | `sc-azure-dev` |
| psq | `sc-azure-psq` |
| prod | `sc-azure-prod` |

Steps:

1. **Project settings → Service connections → New service connection → Azure Resource Manager**.
2. Choose **Workload identity federation (automatic)**. This is the recommended option because it uses no secrets.
3. Scope level: **Subscription**. Pick the subscription for that environment. Leave Resource group empty.
4. Service connection name: `sc-azure-dev` (or psq / prod).
5. Leave **"Grant access permission to all pipelines"** unticked. Authorize each pipeline on its first run instead.

Then give the service connection's identity these roles. Find its identity under *Service connection → Manage App registration / Manage service connection roles*.

| Role | Scope | Why |
|---|---|---|
| **Contributor** | Subscription | Create the RG, network, VM and storage. Includes `Microsoft.KeyVault/vaults/deploy/action`, which `getSecret()` needs. |
| **Role Based Access Control Administrator** (or User Access Administrator) | Subscription | Create the *Storage Blob Data Reader* (and optional KV) role assignments |
| **Key Vault Secrets Officer** | Key Vault | Only needed if you generate passwords from the pipeline (Option B) |

```bash
SP_ID=<appId-of-service-connection>
SUB=/subscriptions/<SUBSCRIPTION-ID>
az role assignment create --assignee $SP_ID --role "Contributor" --scope $SUB
az role assignment create --assignee $SP_ID --role "Role Based Access Control Administrator" --scope $SUB
az role assignment create --assignee $SP_ID --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show -n <KEYVAULT-NAME> --query id -o tsv)
```

## 6. Create the Azure DevOps environments (approvals)

The deploy pipelines target the Azure DevOps environments `azure-dev`, `azure-psq` and `azure-prod`.

1. **Pipelines → Environments → New environment**. Name it `azure-dev` with resource *None*. Repeat for `azure-psq` and `azure-prod`.
2. On `azure-psq` and `azure-prod`, open **⋯ → Approvals and checks → Approvals** and add the approvers.

If an environment doesn't exist when a pipeline first runs, Azure DevOps creates it automatically, but without approvals.

## 7. Create the 6 pipelines

Push this repo to Azure Repos, then repeat the steps below for each YAML.

1. **Pipelines → New pipeline → Azure Repos Git →** select the repo.
2. **Existing Azure Pipelines YAML file** → branch `main` → choose the path from the table below.
3. Click **Save** (from the Run ▾ dropdown), then **Rename/move** the pipeline to a clear name. Optionally put it in a folder named after the environment.

| Pipeline name | YAML path | Trigger |
|---|---|---|
| dev-whatif | `/pipelines/dev/dev-whatif.yml` | push to main (Bicep / dev params) + manual |
| dev-deploy | `/pipelines/dev/dev-deploy.yml` | manual |
| psq-whatif | `/pipelines/psq/psq-whatif.yml` | push to main (Bicep / psq params) + manual |
| psq-deploy | `/pipelines/psq/psq-deploy.yml` | manual |
| prod-whatif | `/pipelines/prod/prod-whatif.yml` | push to main (Bicep / prod params) + manual |
| prod-deploy | `/pipelines/prod/prod-deploy.yml` | manual |

To run the what-if on pull requests: **Repos → Branches → main → Branch policies → Build validation** → add the `<env>-whatif` pipeline.

## 8. Run

1. Run **`dev-whatif`** and check the what-if output in the logs.
2. Run **`dev-deploy`**. Tick *Generate VM admin username/password* if you skipped step 4. The pipeline does the following:
   - **Prepare stage:** (optional) creates the password in Key Vault, then runs validate and what-if.
   - **Deploy stage:** waits for approval if one is configured on the environment, then runs `az deployment sub create`. The VM gets its credentials from Key Vault.
3. On the first run, click **Permit** when asked to authorize the service connection or environment.
4. Promote the same commit to **psq** and then **prod** the same way.

### Verify the managed identity and storage access

From inside the VM:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az login --identity
az storage blob list --account-name <storageAccountName> --container-name data --auth-mode login -o table
```

## Running locally (optional)

```bash
az login
./scripts/bicep-deploy.sh whatif environments/dev/dev.parameters.json
./scripts/bicep-deploy.sh create environments/dev/dev.parameters.json
```

## Troubleshooting

| Error | Fix |
|---|---|
| `Placeholders like <...> are still present` | Fill every `<...>` value in the parameter file |
| `KeyVaultParameterReferenceSecretRetrieveFailed` / *not enabled for template deployment* | `az keyvault update -n <kv> --enabled-for-template-deployment true` |
| `SecretNotFound` | Run `passwordgenerator.sh` for that environment first |
| `AuthorizationFailed ... roleAssignments/write` | Give the service connection the *Role Based Access Control Administrator* role |
| `StorageAccountAlreadyTaken` | Change `storageAccountName`; it must be globally unique |
| `SkuNotAvailable` | That VM size or zone is not available in the region. Change `vmSize` or `availabilityZone` |
| Can't SSH or RDP to the VM | By design, there is no public IP and no inbound NSG rules. Use Azure Bastion, a VPN, or `az vm run-command` |
