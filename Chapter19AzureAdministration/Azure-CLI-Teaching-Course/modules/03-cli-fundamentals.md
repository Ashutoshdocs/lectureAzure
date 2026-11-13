# Module 03 – Azure CLI Fundamentals

## Objective
Learn command structure, help, output formats, queries, variables, and command chaining.

## 1. Command structure
Typical pattern:

```text
az <service> <resource> <action> [options]
```

Examples:
```bash
az group list
az group show --name "<RESOURCE_GROUP>"
az vm list --output table
```

## 2. Help and discovery
```bash
az --help
az vm --help
az vm create --help
az find "virtual machine"
```

## 3. Output formats
```bash
az account list --output table
az account list --output json
az account list --output yaml
az account list --output tsv
```

Common aliases: `-o` for `--output`.

## 4. Query with JMESPath
```bash
az account list --query "[].{Name:name, Subscription:id, State:state}" --output table
az group list --query "[].name" --output tsv
```

Query examples:
- `[].name` – return each object's name.
- `[0]` – return the first array item.
- `{Name:name, Location:location}` – project selected fields.

## 5. Variables

Bash:
```bash
LOCATION="centralindia"
RG="rg-azcli-training"
echo "$RG"
```

PowerShell:
```powershell
$LOCATION = "centralindia"
$RG = "rg-azcli-training"
Write-Output $RG
```

## 6. Subscription context
```bash
az account show --output table
az account list --output table
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

## 7. Extensions
```bash
az extension list --output table
az extension search --query "account"
```

Install an extension only when a command or feature requires it:
```bash
az extension add --name "<EXTENSION_NAME>"
```

## Lab task
List all resource groups in table format, then show only their names using `--query` and TSV output. Explain the difference between JSON and table output.
