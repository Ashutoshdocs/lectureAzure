# Azure Deployment Stacks – Hands-on Lecture Practicals

This lecture pack contains three practicals that teach Azure Deployment Stacks using Bicep. The examples target **Central US** and use dedicated resource groups.

## Folder structure

1. `01-stack-create-vm-and-storage/` – create a Linux VM and Storage Account using a Bicep template deployed as a stack.
2. `02-why-deployment-stacks/` – compare ordinary Bicep/ARM deployments with Deployment Stacks, including ownership, deny settings, and controlled deletion.
3. `03-stack-commands-and-resource-lifecycle/` – important stack commands and hands-on experiments: remove a resource declaration, redeploy, detach a resource, delete a resource, and inspect stack state.

Each practical has its own detailed `README.md`, Bicep files, and command scripts where useful.

## Prerequisites

- Azure CLI with the `deployment-stacks` extension/commands available. Update Azure CLI and install/update the extension if prompted by the CLI.
- Bicep support: `az bicep install` (or `az bicep upgrade`).
- An Azure subscription and permission to create resource groups, deploy resources, and create deployment stacks.
- For deny settings and managed resources, the operator may need additional permissions such as `Microsoft.Authorization/denyAssignments/write` and permission to manage deployment stacks.
- Bash shell (Azure Cloud Shell Bash, Linux, or WSL).

Check the environment:

```bash
az version
az bicep version
az stack group --help
```

> Deployment Stack commands and some flags can vary with Azure CLI/extension versions. If `az stack group` is unavailable, update Azure CLI and install/update the `deployment-stacks` extension as directed by `az extension list-available --output table` and `az extension add --name deployment-stacks`.

## Important terminology

- **Bicep** is the language used to declare Azure resources.
- **ARM deployment** evaluates and deploys a Bicep/ARM template.
- **Deployment Stack** is an Azure resource that manages a collection of resources deployed from a template and records the relationship between the stack and its managed resources.
- **Action on unmanaged resources** controls what happens to resources that were previously managed by a stack but are no longer declared in the updated template:
  - `detachAll` – remove stack management but leave the Azure resources.
  - `deleteResources` – delete resources removed from the template.
- **Deny settings** can restrict operations on resources managed by the stack. They are not a substitute for RBAC, policy, or a security review.

## Safe lab rules

- Use a dedicated resource group for each practical.
- Run `what-if` before every create/update.
- Review `action-on-unmanage` and deny settings carefully.
- Never experiment with `deleteResources` or restrictive deny settings in a shared/production resource group.
- A stack is not a backup, and it does not protect data from every deletion or administrative path.
- Do not put passwords, access keys, or other secrets in Bicep source or plain-text parameter files.

## Cost

The VM, disks, public IP, and Storage Account can incur charges. Delete the dedicated lab resource groups after class.

## Official command references

- [Azure Deployment Stacks with Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks)
- [Azure CLI – az stack group](https://learn.microsoft.com/cli/azure/stack/group)
- [Azure CLI – az stack-whatif group](https://learn.microsoft.com/cli/azure/stack-whatif/group)

Note: the stack-specific preview command is `az stack-whatif group create`; the ordinary Bicep/ARM preview command remains `az deployment group what-if`.
