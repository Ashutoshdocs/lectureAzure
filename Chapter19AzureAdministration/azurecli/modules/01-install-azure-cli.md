# Module 01 – Install Azure CLI on Windows and Linux

## Objective
Install the Azure CLI, confirm that the `az` command works, and understand how to update it.

## What is Azure CLI?
Azure CLI is a cross-platform command-line tool for creating, managing, and querying Azure resources. Commands start with `az`, for example `az group list`.

## Part A – Windows

### Option 1: WinGet
Open PowerShell or Windows Terminal as an administrator (if your machine requires elevated installation permissions):

```powershell
winget install --exact --id Microsoft.AzureCLI
```

Close and reopen the terminal, then verify:

```powershell
az version
az --help
Get-Command az
```

### Option 2: MSI installer
1. Open the official [Azure CLI installation page](https://learn.microsoft.com/cli/azure/install-azure-cli).
2. Download the 64-bit Windows MSI installer.
3. Run the installer and complete the wizard.
4. Open a new PowerShell window and run `az version`.

### Update on Windows
Use the current installation method's update process. With WinGet:

```powershell
winget upgrade --exact --id Microsoft.AzureCLI
```

## Part B – Ubuntu Linux

The following uses Microsoft's official Debian/Ubuntu installation script. Run in Bash:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Verify:

```bash
az version
which az
az --help
```

Update the package index and Azure CLI package:

```bash
sudo apt-get update
sudo apt-get install --only-upgrade -y azure-cli
```

If the package is not found, revisit the official installation page and confirm the Microsoft package repository is configured for your Ubuntu release.

## Part C – First CLI checks

```bash
az version
az --help
az find "az group create"
az configure
```

`az find` can help discover commands. `az configure` can set preferences such as default output format.

## Teaching explanation
- `az` is the root command.
- `group`, `vm`, `network`, and `storage` are command groups.
- `create`, `list`, `show`, `update`, and `delete` are common actions.
- Azure CLI is not the same as Azure PowerShell (`Az` module).

## Lab task
1. Install Azure CLI on a Windows computer.
2. Install it on an Ubuntu VM.
3. Capture the output of `az version` from both systems.
4. Explain why a new terminal window may be needed after installation.

## Troubleshooting
- **`az` is not recognized:** reopen the terminal; check installation and PATH.
- **Linux package errors:** inspect repository configuration and use the official installation guide for your distribution.
- **Permission denied:** use `sudo` for system package installation.
