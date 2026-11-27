# Practical 4 – Separate ARM Template and Parameter Files

## Learning objectives

- Separate reusable infrastructure definition from environment-specific values.
- Understand parameter types, default values, allowed values, min/max constraints and secureString.
- Use separate parameter files for DEV and PROD.
- Deploy the same template to multiple environments.

## Files

- `template.json` – reusable Storage Account template.
- `dev.parameters.json` – DEV values.
- `prod.parameters.json` – PROD values.

## 1. Understand template vs parameter file

The template describes *what* Azure should create. The parameter file supplies *which values* should be used for a particular deployment.

The template defines:
- `storageAccountName` – string
- `location` – string with default
- `skuName` – string with allowed values
- `environment` – string with allowed values
- `enableBlobPublicAccess` – bool

## 2. Create resource group

```bash
az login
az group create --name rg-arm-parameters --location centralindia
```

## 3. Validate DEV

```bash
az deployment group validate \
  --resource-group rg-arm-parameters \
  --template-file template.json \
  --parameters @dev.parameters.json
```

## 4. Preview and deploy DEV

```bash
az deployment group what-if \
  --resource-group rg-arm-parameters \
  --template-file template.json \
  --parameters @dev.parameters.json

az deployment group create \
  --name deploy-storage-dev \
  --resource-group rg-arm-parameters \
  --template-file template.json \
  --parameters @dev.parameters.json
```

## 5. Deploy PROD with the same template

Before deploying, replace the sample Storage Account name in `prod.parameters.json` with a globally unique name.

```bash
az deployment group what-if \
  --resource-group rg-arm-parameters \
  --template-file template.json \
  --parameters @prod.parameters.json

az deployment group create \
  --name deploy-storage-prod \
  --resource-group rg-arm-parameters \
  --template-file template.json \
  --parameters @prod.parameters.json
```

For a realistic environment separation, deploy DEV and PROD into separate resource groups and use separate globally unique Storage Account names.

## 6. Parameter file formats

ARM deployment parameter files use a top-level `$schema`, `contentVersion`, and `parameters` object. Each parameter has a `value` property. Do not put secrets in ordinary JSON parameter files.

For secure values, use a secure parameter and supply the value through a protected pipeline/secret store or a Key Vault parameter reference. Never commit secrets to Git.

## Teaching discussion

- Why separate template and parameter files?
- Can the same template deploy to multiple regions?
- What happens when a value is not supplied and has no default?
- Why use `allowedValues`?
- Why should secrets not be committed in parameter files?

## Cleanup

```bash
az group delete --name rg-arm-parameters --yes --no-wait
```
