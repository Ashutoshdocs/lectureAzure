# Practical 1 – ARM Template Basics

## Learning objectives

- Understand the JSON structure of an ARM template.
- Explain `$schema`, `contentVersion`, `parameters`, `variables`, `resources` and `outputs`.
- Validate, preview and deploy a template.
- Understand that ARM templates are declarative.

## Main template

Open `template.json`. It creates a simple Log Analytics workspace as a teaching resource, with configurable name and location. This demonstrates a resource declaration and outputs without requiring a VM.

## 1. Create a resource group

```bash
az login
RG="rg-arm-basics"
az group create --name "$RG" --location centralindia
```

## 2. Understand the template sections

- `$schema`: identifies the ARM template schema.
- `contentVersion`: version of this template document.
- `parameters`: values supplied at deployment time.
- `variables`: reusable expressions inside the template.
- `resources`: Azure resources to create or update.
- `outputs`: values returned after deployment.

## 3. Validate

```bash
az deployment group validate \
  --resource-group "$RG" \
  --template-file template.json \
  --parameters workspaceName="lawarm$RANDOM"
```

## 4. Preview

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file template.json \
  --parameters workspaceName="lawarm$RANDOM"
```

For a consistent name across commands, set it once:

```bash
WORKSPACE="lawarm$RANDOM"
```

## 5. Deploy

```bash
az deployment group create \
  --name arm-basics-deployment \
  --resource-group "$RG" \
  --template-file template.json \
  --parameters workspaceName="$WORKSPACE"
```

## 6. Verify

```bash
az resource list --resource-group "$RG" --output table
```

## Teaching discussion

1. Is an ARM template imperative or declarative?
2. What is the difference between a parameter and a variable?
3. What is the purpose of outputs?
4. Does `what-if` create the resource?
5. What happens if you deploy the same template again?

## Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```
