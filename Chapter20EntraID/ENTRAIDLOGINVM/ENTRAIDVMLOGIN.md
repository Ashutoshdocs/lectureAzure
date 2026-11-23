# 📘 Azure Virtual Machines – Microsoft Entra ID Authentication Demo

## 1. Objective

In this practical, we will learn how to integrate Azure Virtual Machines with **Microsoft Entra ID** and allow users to log in using their organizational Microsoft Entra credentials.

Instead of managing separate usernames and passwords for every VM, we can centrally manage VM login permissions using Microsoft Entra ID and Azure RBAC.

### What we will implement

1. Create an Azure Linux VM (Ubuntu 24.04).
2. Create an Azure Windows VM (Windows Server 2022).
3. Enable System-Assigned Managed Identity.
4. Install the Microsoft Entra login VM extensions.
5. Create or select Microsoft Entra users.
6. Assign VM login permissions using Azure RBAC.
7. Log in to Linux using Microsoft Entra ID over SSH.
8. Log in to Windows using Microsoft Entra ID over RDP.
9. Test user access and administrator access.
10. Remove access and verify that login is denied.

---

## 2. Architecture

```text
                 Microsoft Entra ID
                         |
                +-------------------+
                |                   |
          User: Admin          User: Developer
                |                   |
                +---------+---------+
                          |
                    Azure RBAC
                          |
              +-----------+-----------+
              |                       |
        VM Administrator         VM User Login
              |                       |
        +-----+------+          +-----+------+
        |            |          |            |
     Linux VM     Windows VM  Linux VM    Windows VM
     Ubuntu       Server 2022 Ubuntu      Server 2022
        |            |          |            |
    SSH Login     RDP Login   SSH Login    RDP Login
        |            |          |            |
        +------------+----------+------------+
                          |
                   Microsoft Entra
                   Authentication
```

## 3. Prerequisites

- Active Azure subscription.
- Microsoft Entra ID tenant.
- Azure CLI installed.
- Permission to create Azure VMs and managed identities.
- Permission to assign Azure RBAC roles.
- A Microsoft Entra user account for testing.
- Windows client for RDP testing.
- SSH client for Linux testing.

### Important concepts

| Component | Purpose |
|---|---|
| Microsoft Entra ID | Centralized user authentication |
| System-Assigned Managed Identity | Allows the VM to obtain an identity in Microsoft Entra ID |
| VM Extension | Enables Entra authentication on the VM |
| Azure RBAC | Controls which users can log in |
| Virtual Machine User Login | Grants standard VM login |
| Virtual Machine Administrator Login | Grants administrator VM login |

**Important:** Managed Identity and user authentication are different things.

- Managed Identity identifies the VM to Azure.
- Microsoft Entra ID authenticates the human user.
- Azure RBAC authorizes the user to log in.

---

# PART 1 – Create the Azure Resources

## 4. Login to Azure

```bash
az login
```

Select the subscription:

```bash
az account list -o table
```

```bash
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

Create a resource group:

```bash
az group create \
  --name rg-entra-vm-demo \
  --location centralindia
```

## 5. Create a Linux VM (Ubuntu 24.04)

Create the Linux VM:

```bash
az vm create \
  --resource-group rg-entra-vm-demo \
  --name vm-linux-entra \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --assign-identity
```

The command creates:

- Linux Virtual Machine
- Network Interface
- Public IP
- OS Disk
- Virtual Network (if not already supplied)
- System-Assigned Managed Identity

Check the VM:

```bash
az vm show \
  -g rg-entra-vm-demo \
  -n vm-linux-entra \
  --query "{Name:name,Identity:identity.type}" \
  -o json
```

Expected identity:

```json
{
  "Name": "vm-linux-entra",
  "Identity": "SystemAssigned"
}
```

## 6. Create a Windows VM (Windows Server 2022)

For the Windows VM, create an administrator password securely.

```bash
read -s -p "Enter Windows VM password: " WINPASS
echo
```

Create the VM:

```bash
az vm create \
  --resource-group rg-entra-vm-demo \
  --name vm-windows-entra \
  --image Win2022Datacenter \
  --size Standard_B2s \
  --admin-username localadmin \
  --admin-password "$WINPASS" \
  --assign-identity
```

Clear the shell variable:

```bash
unset WINPASS
```

Check the VM:

```bash
az vm show \
  -g rg-entra-vm-demo \
  -n vm-windows-entra \
  --query identity.type \
  -o tsv
```

Expected:

```text
SystemAssigned
```

**Teaching point:** The local administrator account is created for initial VM administration and recovery. Our objective is to use Microsoft Entra ID for normal user authentication.

---

# PART 2 – Enable Microsoft Entra ID on Linux VM

## 7. Install Microsoft Entra Login Extension

For Linux, Azure uses the following extension:

`AADSSHLoginForLinux`

Run:

```bash
az vm extension set \
  --publisher Microsoft.Azure.ActiveDirectory \
  --name AADSSHLoginForLinux \
  --resource-group rg-entra-vm-demo \
  --vm-name vm-linux-entra
```

Check extension status:

```bash
az vm extension list \
  --resource-group rg-entra-vm-demo \
  --vm-name vm-linux-entra \
  -o table
```

Expected extension:

```text
AADSSHLoginForLinux
ProvisioningState: Succeeded
```

### What happens in the background?

1. Azure installs the Entra SSH login extension.
2. The extension installs the required Linux authentication packages.
3. The VM uses its System-Assigned Managed Identity.
4. The VM becomes capable of accepting Microsoft Entra-based SSH authentication.
5. Azure RBAC determines which users can log in.

---

# PART 3 – Enable Microsoft Entra ID on Windows VM

## 8. Install Microsoft Entra Login Extension

For Windows, Azure uses:

`AADLoginForWindows`

Run:

```bash
az vm extension set \
  --publisher Microsoft.Azure.ActiveDirectory \
  --name AADLoginForWindows \
  --resource-group rg-entra-vm-demo \
  --vm-name vm-windows-entra
```

Check extension status:

```bash
az vm extension list \
  --resource-group rg-entra-vm-demo \
  --vm-name vm-windows-entra \
  -o table
```

Expected:

```text
AADLoginForWindows
ProvisioningState: Succeeded
```

### What happens in the background?

1. The extension communicates with Microsoft Entra ID.
2. The VM performs Microsoft Entra device registration and join.
3. The VM can authenticate supported Microsoft Entra user accounts.
4. Azure RBAC determines which users can access the VM.

**Important:** Use supported Windows Server 2022 or 2025 Desktop Experience images. The Windows VM must have a System-Assigned Managed Identity before installing this extension.

---

# PART 4 – Configure Azure RBAC

## 9. Understand the Two Important Roles

Azure provides two important built-in roles for VM sign-in.

| Role | Permission |
|---|---|
| Virtual Machine User Login | Standard user login |
| Virtual Machine Administrator Login | Administrator login |

### Scenario

Suppose we have two Microsoft Entra users:

- admin@yourdomain.com
- developer@yourdomain.com

We want:

| User | Linux VM | Windows VM |
|---|---|---|
| Admin | Administrator | Administrator |
| Developer | Standard User | Standard User |

This can be achieved through Azure RBAC.

## 10. Get Microsoft Entra User Object IDs

Find the user object ID:

```bash
az ad user show \
  --id admin@yourdomain.com \
  --query id \
  -o tsv
```

For the developer:

```bash
az ad user show \
  --id developer@yourdomain.com \
  --query id \
  -o tsv
```

Store the IDs:

```bash
ADMIN_ID=$(az ad user show \
  --id admin@yourdomain.com \
  --query id -o tsv)

DEV_ID=$(az ad user show \
  --id developer@yourdomain.com \
  --query id -o tsv)
```

## 11. Get VM Resource IDs

```bash
LINUX_VM_ID=$(az vm show \
  -g rg-entra-vm-demo \
  -n vm-linux-entra \
  --query id -o tsv)

WINDOWS_VM_ID=$(az vm show \
  -g rg-entra-vm-demo \
  -n vm-windows-entra \
  --query id -o tsv)
```

## 12. Assign Administrator Login Role

Give the administrator user access to Linux:

```bash
az role assignment create \
  --assignee-object-id "$ADMIN_ID" \
  --assignee-principal-type User \
  --role "Virtual Machine Administrator Login" \
  --scope "$LINUX_VM_ID"
```

Give the administrator access to Windows:

```bash
az role assignment create \
  --assignee-object-id "$ADMIN_ID" \
  --assignee-principal-type User \
  --role "Virtual Machine Administrator Login" \
  --scope "$WINDOWS_VM_ID"
```

## 13. Assign Standard User Login Role

Give the developer access to Linux:

```bash
az role assignment create \
  --assignee-object-id "$DEV_ID" \
  --assignee-principal-type User \
  --role "Virtual Machine User Login" \
  --scope "$LINUX_VM_ID"
```

Give the developer access to Windows:

```bash
az role assignment create \
  --assignee-object-id "$DEV_ID" \
  --assignee-principal-type User \
  --role "Virtual Machine User Login" \
  --scope "$WINDOWS_VM_ID"
```

### Verify role assignments

```bash
az role assignment list \
  --scope "$LINUX_VM_ID" \
  --include-inherited \
  -o table
```

For Windows:

```bash
az role assignment list \
  --scope "$WINDOWS_VM_ID" \
  --include-inherited \
  -o table
```

**Important teaching point:** Having Owner or Contributor permissions on an Azure VM does not automatically grant Microsoft Entra VM sign-in permissions.

---

# PART 5 – Login to Linux VM Using Microsoft Entra ID

## 14. Install Azure CLI SSH Extension

On your client machine:

```bash
az extension add --name ssh
```

Login using the Microsoft Entra user:

```bash
az login
```

If you are using a different user, sign in with that user's account.

Check the logged-in account:

```bash
az account show \
  --query user.name \
  -o tsv
```

## 15. Connect to Linux VM

Run:

```bash
az ssh vm \
  --resource-group rg-entra-vm-demo \
  --name vm-linux-entra
```

The command obtains an ephemeral SSH certificate and connects using Microsoft Entra authentication.

The user will authenticate through the Microsoft Entra sign-in flow as required.

### Verify the Linux login

Inside the VM:

```bash
whoami
```

```bash
id
```

```bash
hostname
```

### Test administrator privileges

For the administrator user:

```bash
sudo whoami
```

Expected:

```text
root
```

For the standard VM user, sudo privileges are not granted by the VM User Login role.

---

# PART 6 – Login to Windows VM Using Microsoft Entra ID

## 16. Get Windows VM Public IP

```bash
az vm show \
  -d \
  -g rg-entra-vm-demo \
  -n vm-windows-entra \
  --query publicIps \
  -o tsv
```

For a secure production setup, prefer Azure Bastion or private network connectivity rather than exposing RDP to the internet.

## 17. Connect Using Remote Desktop

On your Windows client:

1. Open Remote Desktop Connection.
2. Enter the Windows VM hostname or reachable DNS name.
3. Open Advanced settings.
4. Select the option **Use a web account to sign in to the remote computer** when using the passwordless/web-account flow.
5. Connect using the VM hostname registered in Microsoft Entra ID.
6. Enter the Microsoft Entra username.
7. Complete the authentication process.

For the conventional Microsoft Entra credential flow, enter the username in this format:

```text
AzureAD\admin@yourdomain.com
```

Authenticate using the user's Microsoft Entra credentials.

### Important Windows requirements

- The client device must satisfy the Microsoft Entra device requirements for the selected RDP authentication method.
- For conventional RDP authentication, use a supported Windows 10 or later client registered or joined to the same tenant.
- The web-account sign-in method requires a hostname rather than an IP address.
- Assign the user one of the two VM Login RBAC roles.
- Ensure the required RDP network connectivity exists.

### Verify Windows login

After connecting:

1. Open PowerShell.
2. Run:

```powershell
whoami
```

3. Open Computer Management.
4. Check the logged-in user's permissions.

For the administrator role, test:

```powershell
whoami /groups
```

---

# PART 7 – Practical RBAC Testing

## 18. Test Case 1: Administrator Login

Login using:

```text
admin@yourdomain.com
```

Expected:

| Test | Expected result |
|---|---|
| Linux SSH login | Successful |
| Linux sudo access | Allowed |
| Windows RDP login | Successful |
| Windows administrator access | Allowed |

## 19. Test Case 2: Standard User Login

Login using:

```text
developer@yourdomain.com
```

Expected:

| Test | Expected result |
|---|---|
| Linux SSH login | Successful |
| Linux sudo access | Not granted by VM User Login |
| Windows RDP login | Successful |
| Windows administrator access | Not granted by VM User Login |

## 20. Test Case 3: Remove User Access

Remove the developer's Linux login permission:

```bash
az role assignment delete \
  --assignee "$DEV_ID" \
  --role "Virtual Machine User Login" \
  --scope "$LINUX_VM_ID"
```

Try logging in again after RBAC changes propagate.

Expected result:

```text
Login denied
```

Existing sessions might remain active until disconnected. Revoking the role assignment does not automatically terminate an already established session.

---

# PART 8 – Azure Portal Demonstration

## 21. Show the Configuration in Azure Portal

Open:

https://portal.azure.com

### Step 1: Show the VM Identity

1. Open Linux VM.
2. Navigate to Identity.
3. Select System assigned.
4. Show Status = On.

Repeat for Windows VM.

### Step 2: Show VM Extensions

1. Open the VM.
2. Select Extensions + applications.
3. Show the installed extension.

Linux:

```text
AADSSHLoginForLinux
```

Windows:

```text
AADLoginForWindows
```

### Step 3: Show RBAC

1. Open the VM.
2. Select Access control (IAM).
3. Open Role assignments.
4. Show the administrator and developer users.
5. Explain the difference between both login roles.

### Step 4: Show Microsoft Entra Users

Open:

https://entra.microsoft.com

Navigate to:

```text
Identity
   |
   +-- Users
         |
         +-- All users
```

Show the users used in the practical.

---

# PART 9 – Troubleshooting

## 22. Common Errors

| Error | Possible solution |
|---|---|
| Extension installation failed | Check VM Agent and extension provisioning status |
| Managed identity missing | Enable System-Assigned Managed Identity |
| Azure role not assigned | Assign VM User Login or VM Administrator Login |
| Linux SSH connection failed | Verify SSH connectivity and Azure CLI SSH extension |
| Windows RDP login failed | Check supported client, username format and RBAC |
| Windows extension failed | Check Entra registration and outbound connectivity |
| Linux sudo denied | Verify whether the user has VM Administrator Login |
| Login denied after role assignment | Allow time for RBAC propagation and refresh authentication |

### Useful Linux commands

```bash
sudo systemctl status walinuxagent
```

```bash
sudo journalctl -u walinuxagent
```

### Useful Windows command

```powershell
dsregcmd /status
```

Look for:

```text
AzureAdJoined : YES
```

Check Windows extension logs:

```text
C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\
```

---

# PART 10 – Security Best Practices

1. Prefer Microsoft Entra authentication instead of sharing local VM credentials.
2. Use Virtual Machine User Login for developers.
3. Reserve Virtual Machine Administrator Login for authorized administrators.
4. Assign RBAC at the smallest practical scope.
5. Use Microsoft Entra MFA and appropriate Conditional Access policies.
6. Restrict SSH and RDP access using NSGs.
7. Prefer Azure Bastion or private connectivity instead of public RDP/SSH exposure.
8. Use managed identities for applications running inside VMs.
9. Regularly review user access and remove unnecessary role assignments.
10. Enable Azure Monitor and audit sign-in activity.

---

# PART 11 – Cleanup

After completing the practical, delete the resource group:

```bash
az group delete \
  --name rg-entra-vm-demo \
  --yes \
  --no-wait
```

This removes the VMs and other resources created inside the resource group.

---

# PART 12 – Interview Questions

**Q1. What is Microsoft Entra ID?**

Microsoft Entra ID is Microsoft's cloud-based identity and access management service. It manages users, groups, authentication and access.

**Q2. Why do we enable System-Assigned Managed Identity on an Azure VM?**

The VM uses its managed identity to communicate with Azure services and obtain tokens without storing credentials.

**Q3. What is the purpose of AADSSHLoginForLinux?**

It enables Microsoft Entra-based SSH authentication for supported Azure Linux VMs.

**Q4. What is the purpose of AADLoginForWindows?**

It enables Microsoft Entra authentication for supported Azure Windows VMs.

**Q5. What is the difference between Virtual Machine User Login and Virtual Machine Administrator Login?**

The first grants standard login access. The second grants administrator login privileges.

**Q6. If a user has Contributor access to a VM, can they automatically log in?**

No. Azure resource management permissions and VM sign-in permissions are separate.

**Q7. Can we remove VM access without deleting the Entra user?**

Yes. Remove the user's VM Login RBAC assignment.

**Q8. What happens if an employee leaves the organization?**

Disabling their Microsoft Entra account prevents further authentication, and their VM RBAC assignments should also be reviewed and removed.

**Q9. Is Managed Identity the same as Microsoft Entra user authentication?**

No. Managed Identity represents the VM or workload. Microsoft Entra user authentication verifies the human user.

**Q10. Can we use Microsoft Entra MFA for VM login?**

Yes, subject to the supported authentication method and Conditional Access configuration.

---

# Final Learning Outcome

After this practical, students should understand how to:

- Create Azure Linux and Windows VMs.
- Enable Microsoft Entra authentication.
- Configure System-Assigned Managed Identity.
- Install the required VM extensions.
- Assign Azure RBAC login roles.
- Connect to Linux using SSH.
- Connect to Windows using RDP.
- Control user access centrally through Microsoft Entra ID.

**Real-world use case:** In an enterprise environment, instead of maintaining separate local accounts on 100 Azure VMs, administrators can centrally manage user access through Microsoft Entra ID and Azure RBAC.

---

## Official Microsoft Documentation

1. [Microsoft Entra ID login for Linux VMs](https://learn.microsoft.com/en-us/entra/identity/devices/howto-vm-sign-in-azure-ad-linux)

2. [Microsoft Entra ID login for Windows VMs](https://learn.microsoft.com/en-us/entra/identity/devices/howto-vm-sign-in-azure-ad-windows)

3. [Azure RBAC documentation](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)

4. [Azure Managed Identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)