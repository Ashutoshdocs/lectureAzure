# Azure Linux VM -- SSH Key Authentication Practical

This practical demonstrates four SSH-key workflows for Azure Linux
Virtual Machines:

1.  Create an SSH key pair locally and use an existing public key when
    creating a VM.
2.  Create and store an SSH public key resource in Azure, then use it to
    create a VM.
3.  Generate a new SSH key pair and add its public key to an existing
    VM.
4.  Recover access when the private key is lost but an old SSH session
    is still available.

> **Important security fact:** A private key cannot be recreated from
> its public key. The file `/home/azureuser/.ssh/authorized_keys`
> contains public keys only. If the private key is lost, generate a new
> key pair and authorize its new public key on the VM.

------------------------------------------------------------------------

## Prerequisites

-   Azure subscription and permission to create resource groups, SSH key
    resources, and Linux VMs.
-   Azure CLI installed and logged in: `az login`.
-   A Linux VM image that supports SSH public-key authentication.
-   Replace the sample names, region, and image as needed.

Example variables (Azure CLI -- Bash):

``` bash
RG="rg-ssh-demo"
LOCATION="centralindia"
VM="vm-ssh-demo"
ADMIN="azureuser"
```

For PowerShell, the same variables can be set like this:

``` powershell
$RG = "rg-ssh-demo"
$LOCATION = "centralindia"
$VM = "vm-ssh-demo"
$ADMIN = "azureuser"
```

Create the resource group:

``` bash
az group create --name "$RG" --location "$LOCATION"
```

------------------------------------------------------------------------

# Part 1 -- Create an SSH key locally and use the existing public key to create an Azure VM

### Step 1: Generate a key pair on your computer

**Linux / macOS / Azure Cloud Shell:**

``` bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/azure_vm_key -C "azure-vm-demo"
```

When prompted, set a passphrase if appropriate. This creates:

-   `~/.ssh/azure_vm_key` -- private key. Keep it secret.
-   `~/.ssh/azure_vm_key.pub` -- public key. This can be uploaded to
    Azure or placed on a VM.

**Windows PowerShell:**

``` powershell
New-Item -ItemType Directory -Force "$HOME\.ssh"
ssh-keygen -t ed25519 -f "$HOME\.ssh\azure_vm_key" -C "azure-vm-demo"
```

### Step 2: Inspect the public key

Linux:

``` bash
cat ~/.ssh/azure_vm_key.pub
```

PowerShell:

``` powershell
Get-Content "$HOME\.ssh\azure_vm_key.pub"
```

Only the `.pub` file is supplied to Azure. Never upload or share the
private key.

### Step 3: Create the VM using that existing public key

Linux / Bash:

``` bash
az vm create \
  --resource-group "$RG" \
  --name "$VM" \
  --location "$LOCATION" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --admin-username "$ADMIN" \
  --authentication-type ssh \
  --ssh-key-values ~/.ssh/azure_vm_key.pub
```

Windows PowerShell (single line):

``` powershell
az vm create --resource-group $RG --name $VM --location $LOCATION --image Ubuntu2404 --size Standard_B1s --admin-username $ADMIN --authentication-type ssh --ssh-key-values "$HOME\.ssh\azure_vm_key.pub"
```

### Step 4: Connect to the VM

Get its public IP:

``` bash
VM_IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
```

Connect:

``` bash
ssh -i ~/.ssh/azure_vm_key "$ADMIN@$VM_IP"
```

PowerShell:

``` powershell
$VM_IP = az vm show -d -g $RG -n $VM --query publicIps -o tsv
ssh -i "$HOME\.ssh\azure_vm_key" "$ADMIN@$VM_IP"
```

**What happened?** Azure placed the supplied public key in the VM user's
`~/.ssh/authorized_keys`. The SSH client proves possession of the
matching private key during authentication.

------------------------------------------------------------------------

# Part 2 -- Create an SSH public key resource in Azure and use it for VM creation

Azure can store an SSH public key as an **Azure SSH public key
resource**. This is not the private key and does not mean Azure can
retrieve or recreate your private key.

### Step 1: Generate a key pair locally

If you already created a key pair in Part 1, you can reuse it.
Otherwise:

``` bash
ssh-keygen -t ed25519 -f ~/.ssh/azure_keyvault_demo -C "azure-ssh-resource-demo"
```

PowerShell:

``` powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azure_keyvault_demo" -C "azure-ssh-resource-demo"
```

### Step 2: Create the Azure SSH key resource

``` bash
az sshkey create \
  --resource-group "$RG" \
  --name "sshkey-demo" \
  --location "$LOCATION" \
  --public-key "@$HOME/.ssh/azure_keyvault_demo.pub"
```

> The `@` tells Azure CLI to read the public-key file. If your CLI
> version or shell does not accept this file syntax, pass the public-key
> text using the `--public-key` argument.

PowerShell alternative:

``` powershell
$PUB = Get-Content "$HOME\.ssh\azure_keyvault_demo.pub" -Raw
az sshkey create --resource-group $RG --name sshkey-demo --location $LOCATION --public-key $PUB
```

### Step 3: Retrieve the public key from the Azure resource

``` bash
az sshkey show \
  --resource-group "$RG" \
  --name "sshkey-demo" \
  --query publicKey \
  --output tsv
```

You can also save the returned public key to a local file if required.
The private key remains on the computer where you generated it.

### Step 4: Create a VM using the Azure SSH key resource

``` bash
az vm create \
  --resource-group "$RG" \
  --name "vm-ssh-azure-resource" \
  --location "$LOCATION" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --admin-username "$ADMIN" \
  --authentication-type ssh \
  --ssh-key-name "sshkey-demo"
```

If your installed Azure CLI version does not expose `--ssh-key-name` for
`az vm create`, retrieve the resource's `publicKey` as shown above and
pass that public-key value with `--ssh-key-values`.

### Step 5: Connect using the matching local private key

``` bash
ssh -i ~/.ssh/azure_keyvault_demo "$ADMIN@<VM_PUBLIC_IP>"
```

**Teaching point:** The Azure SSH key resource stores the public key for
reuse. The matching private key must still be available to the SSH
client.

------------------------------------------------------------------------

# Part 3 -- Generate a new key pair and add it to an existing VM

Use this workflow when you want a second laptop, a new administrator, or
a replacement key to access a VM. Do not remove the existing authorized
key until the new login has been tested.

### Step 1: Generate a new key pair on the new computer

``` bash
ssh-keygen -t ed25519 -f ~/.ssh/azure_vm_key_new -C "replacement-access"
```

PowerShell:

``` powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azure_vm_key_new" -C "replacement-access"
```

### Step 2: Display and copy the new public key

Linux:

``` bash
cat ~/.ssh/azure_vm_key_new.pub
```

PowerShell:

``` powershell
Get-Content "$HOME\.ssh\azure_vm_key_new.pub"
```

Copy the complete single-line public key (starts with `ssh-ed25519`).

### Step 3: Log in to the VM using the currently working key

``` bash
ssh -i ~/.ssh/azure_vm_key "$ADMIN@<VM_PUBLIC_IP>"
```

### Step 4: Add the new public key to `authorized_keys`

Run these commands **inside the VM**. Paste the actual public-key line
in place of the sample text:

``` bash
mkdir -p /home/azureuser/.ssh
chmod 700 /home/azureuser/.ssh
echo 'ssh-ed25519 AAAA... replacement-access' >> /home/azureuser/.ssh/authorized_keys
chmod 600 /home/azureuser/.ssh/authorized_keys
chown -R azureuser:azureuser /home/azureuser/.ssh
```

If the VM login account is not `azureuser`, replace the path and owner
with the actual account.

### Step 5: Test the new key from a second terminal

``` bash
ssh -i ~/.ssh/azure_vm_key_new "$ADMIN@<VM_PUBLIC_IP>"
```

Only after the new key works should you consider removing the old
public-key line from `authorized_keys`.

**Teaching point:** One `authorized_keys` file can contain multiple
public keys, one per line. Each corresponding private key can
authenticate independently.

------------------------------------------------------------------------

# Part 4 -- Private key lost, but you are still logged in to the VM

## Can we create the private key from `authorized_keys`?

**No. This is cryptographically infeasible.** The file:

``` text
/home/azureuser/.ssh/authorized_keys
```

contains public keys, not private keys. A public key is designed to be
shared. It cannot be used to derive the corresponding private key.

Do not confuse these files:

  File                Purpose                                 Secret?
  ------------------- --------------------------------------- ---------
  `id_ed25519`        Private key, held by the client         Yes
  `id_ed25519.pub`    Public key, shared with servers         No
  `authorized_keys`   List of public keys allowed to log in   No

## Correct recovery method: create a replacement key pair

### Step 1: While the existing SSH session is still open, generate a new key pair on your own computer

Do this on your **local computer**, not on the VM:

``` bash
ssh-keygen -t ed25519 -f ~/.ssh/azure_vm_recovery -C "recovered-vm-access"
```

PowerShell:

``` powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azure_vm_recovery" -C "recovered-vm-access"
```

### Step 2: Display the new public key on your computer

``` bash
cat ~/.ssh/azure_vm_recovery.pub
```

Copy the complete line.

### Step 3: In the still-open VM session, append the new public key

``` bash
echo 'ssh-ed25519 AAAA... recovered-vm-access' >> /home/azureuser/.ssh/authorized_keys
chmod 700 /home/azureuser/.ssh
chmod 600 /home/azureuser/.ssh/authorized_keys
chown -R azureuser:azureuser /home/azureuser/.ssh
```

Replace the example line with the exact public key copied in Step 2.

### Step 4: Open a new terminal and test the replacement private key

``` bash
ssh -i ~/.ssh/azure_vm_recovery azureuser@<VM_PUBLIC_IP>
```

Keep the original session open until the new connection succeeds.

### What if the user is already disconnected?

If the old private key is lost and there is no active session or other
working login, use an authorized recovery path such as:

-   Azure Portal: VM → **Run command** → **RunShellScript**, to append a
    newly generated public key to the correct user's `authorized_keys`.
-   Azure CLI: `az vm user update` to update the VM user's SSH public
    key, where supported for the VM and image.
-   Azure VMAccess extension / supported VM access reset workflow.

The exact recovery route depends on the VM image, permissions, and
available Azure access. You need sufficient Azure permissions to perform
VM-level recovery.

------------------------------------------------------------------------

## Troubleshooting and verification

On the VM:

``` bash
ls -la /home/azureuser/.ssh
cat /home/azureuser/.ssh/authorized_keys
```

Check permissions:

``` bash
stat -c '%a %U:%G %n' /home/azureuser/.ssh
stat -c '%a %U:%G %n' /home/azureuser/.ssh/authorized_keys
```

Expected permissions are normally:

-   `.ssh` directory: `700`
-   `authorized_keys`: `600`
-   Both owned by the target login user.

On the client, use verbose SSH output to troubleshoot:

``` bash
ssh -vvv -i ~/.ssh/azure_vm_recovery azureuser@<VM_PUBLIC_IP>
```

Common causes of failure:

-   Wrong private key selected with `-i`.
-   Public key was pasted incompletely or with line breaks.
-   Public key was added to the wrong user's home directory.
-   Incorrect `.ssh` or `authorized_keys` ownership/permissions.
-   Network Security Group or firewall blocks TCP port 22.
-   SSH service is not running or the VM is not reachable.

## Key takeaways

1.  The **private key stays with the client**. Never put it in
    `authorized_keys`.
2.  The **public key goes on the VM** in the target user's
    `authorized_keys` file.
3.  Azure SSH public key resources store public keys, not private keys.
4.  A lost private key cannot be reconstructed from a public key.
5.  If you still have access, generate a replacement pair, append its
    public key, and test it before closing the working session.
6.  Keep a secure backup of private keys and protect them with an
    appropriate passphrase.
