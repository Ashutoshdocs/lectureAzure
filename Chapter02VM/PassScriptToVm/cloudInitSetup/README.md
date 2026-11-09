# Azure VM Cloud-Init Practical --- NGINX Web Server

This practical creates an Ubuntu 24.04 virtual machine in Azure and uses
**Cloud-Init** to configure it automatically on its first boot.

At the end, you will have: - An Ubuntu Linux VM - NGINX installed
automatically - A custom HTML landing page served by NGINX - HTTP access
through the VM's public IP on port `80` - SSH access to the VM

## 1. Project files

Keep these files in the same working directory:

``` text
Azure-Cloud-Init/
├── cloud-init.yaml
├── create-vm.ps1
└── README.md
```

**Important:** These are three separate files. Do not paste the
PowerShell script or the standalone HTML page into `cloud-init.yaml`.

The HTML page is already embedded in the `write_files` section of
`cloud-init.yaml`, so you do not need a separate `index.html` file.

## 2. Prerequisites

1.  An Azure subscription with permission to create a resource group,
    VM, public IP and network security group rules.
2.  Azure CLI installed on your Windows computer.
3.  PowerShell (Windows PowerShell 5.1 or PowerShell 7).
4.  An authenticated Azure CLI session.

Check the tools:

``` powershell
az version
```

Sign in:

``` powershell
az login
```

If you have more than one subscription, select the intended one:

``` powershell
az account list --output table
az account set --subscription "<SUBSCRIPTION-ID-OR-NAME>"
az account show --output table
```

## 3. Create `cloud-init.yaml`

Create a file named exactly `cloud-init.yaml` in the project directory.

Paste the Cloud-Init configuration into it. Its structure should look
like this:

``` yaml
#cloud-config

package_update: true
package_upgrade: true

packages:
  - nginx

write_files:
  - path: /var/www/html/index.html
    permissions: "0644"
    owner: root:root
    content: |
      <!-- Paste the complete HTML page here, indented beneath content: -->

runcmd:
  - systemctl enable nginx
  - systemctl restart nginx
```

Replace the HTML comment with the **complete HTML document** from the
practical. Every line of the HTML content must remain indented beneath
`content: |` (typically six spaces before the HTML lines, as in the
supplied YAML).

### What each Cloud-Init section does

  -----------------------------------------------------------------------
  Setting                             Purpose
  ----------------------------------- -----------------------------------
  `#cloud-config`                     Identifies the file as Cloud-Init
                                      configuration

  `package_update: true`              Refreshes the Ubuntu package index

  `package_upgrade: true`             Installs available package upgrades

  `packages`                          Installs NGINX

  `write_files`                       Writes the custom web page to
                                      `/var/www/html/index.html`

  `runcmd`                            Enables NGINX at boot and restarts
                                      it
  -----------------------------------------------------------------------

**YAML indentation matters.** Use spaces, not tabs. The `runcmd:`
section must be at the top level, aligned with `packages:` and
`write_files:`.

## 4. Create `create-vm.ps1`

Create a file named `create-vm.ps1` and paste the PowerShell script
below.

``` powershell
#=========================================================
# Azure VM Creation using Username/Password + Cloud-Init
#=========================================================

$ErrorActionPreference = "Stop"

# Variables
$ResourceGroup = "CloudInit-RG"
$Location      = "centralindia"
$VMName        = "cloudinit-vm01"
$VMSize        = "Standard_B1s"
$Image         = "Ubuntu2404"

$Username      = "azureuser"
$SecurePassword = Read-Host "Enter a strong VM password" -AsSecureString
$BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)

try {
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

    $CloudInitFile = Join-Path $PSScriptRoot "cloud-init.yaml"

    if (-not (Test-Path $CloudInitFile)) {
        throw "Cloud-Init file not found: $CloudInitFile"
    }

    Write-Host "`nCreating resource group..."
    az group create --name $ResourceGroup --location $Location --output table
    if ($LASTEXITCODE -ne 0) { throw "Resource group creation failed." }

    Write-Host "`nCreating Ubuntu VM. First-boot provisioning may take several minutes..."
    az vm create `
        --resource-group $ResourceGroup `
        --name $VMName `
        --image $Image `
        --size $VMSize `
        --admin-username $Username `
        --admin-password $Password `
        --authentication-type password `
        --custom-data $CloudInitFile `
        --public-ip-sku Standard `
        --output json

    if ($LASTEXITCODE -ne 0) { throw "VM creation failed." }

    Write-Host "`nOpening HTTP port 80..."
    az vm open-port `
        --resource-group $ResourceGroup `
        --name $VMName `
        --port 80 `
        --priority 1100

    if ($LASTEXITCODE -ne 0) { throw "Could not create the port 80 rule." }

    Write-Host "`nRetrieving public IP..."
    $PublicIP = az vm show `
        --resource-group $ResourceGroup `
        --name $VMName `
        --show-details `
        --query publicIps `
        --output tsv

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($PublicIP)) {
        throw "Could not retrieve the VM public IP."
    }

    Write-Host "`n==============================================="
    Write-Host "VM deployment command completed"
    Write-Host "==============================================="
    Write-Host "VM name       : $VMName"
    Write-Host "Resource group: $ResourceGroup"
    Write-Host "Username      : $Username"
    Write-Host "Public IP     : $PublicIP"
    Write-Host "Website       : http://$PublicIP"
    Write-Host "SSH           : ssh $Username@$PublicIP"
    Write-Host ""
    Write-Host "Allow a few minutes for Cloud-Init to finish before testing the website."
}
finally {
    if ($BSTR -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
    $Password = $null
}
```

The script prompts for the password rather than storing a password in
the `.ps1` file or printing it to the console. Choose a strong password
that meets Azure's Linux VM password requirements.

> Note: The password is still passed to the Azure CLI process because
> the VM creation command requires it. For production environments,
> prefer SSH-key authentication or an approved secret-management
> workflow.

## 5. Execute the practical

Open PowerShell and change to the directory containing the two files:

``` powershell
cd "C:\Path\To\Azure-Cloud-Init"
```

Confirm both files exist:

``` powershell
Get-ChildItem
```

Run the script:

``` powershell
.\create-vm.ps1
```

If PowerShell blocks script execution for this session, you can run:

``` powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\create-vm.ps1
```

Enter the VM password when prompted. The script then:

1.  Creates the resource group.
2.  Creates the Ubuntu 24.04 VM.
3.  Supplies `cloud-init.yaml` as custom data.
4.  Opens inbound TCP port `80`.
5.  Retrieves and displays the public IP.

The Azure VM creation operation can take several minutes. Cloud-Init may
continue configuring the guest OS after the Azure VM resource has been
created, so allow additional time before checking the website.

## 6. Open the website

Use the public IP printed by the script:

``` text
http://<PUBLIC-IP>
```

You should see the **Azure Cloud-Init Practical** page, including the
provisioning-success message and the list of tasks performed.

Test from PowerShell:

``` powershell
curl.exe http://<PUBLIC-IP>
```

If the page does not appear immediately, wait a few minutes and retry.

## 7. Verify Cloud-Init inside the VM

Connect over SSH:

``` powershell
ssh azureuser@<PUBLIC-IP>
```

Check Cloud-Init status:

``` bash
sudo cloud-init status --long
```

A successful first-boot run should report `status: done`.

Check NGINX:

``` bash
sudo systemctl status nginx --no-pager
```

Check that the page exists:

``` bash
ls -l /var/www/html/index.html
```

Test locally from inside the VM:

``` bash
curl -I http://localhost
curl http://localhost
```

Review Cloud-Init logs if provisioning failed:

``` bash
sudo tail -n 100 /var/log/cloud-init.log
sudo tail -n 100 /var/log/cloud-init-output.log
```

Useful files: - `/var/log/cloud-init.log` --- Cloud-Init processing
details. - `/var/log/cloud-init-output.log` --- output from commands run
during provisioning. - `/var/lib/cloud/` --- Cloud-Init instance state
and cached data.

## 8. Understand the execution flow

``` text
PowerShell script
       |
       v
Azure CLI: az vm create
       |
       v
Azure creates VM and attaches custom data
       |
       v
Ubuntu VM boots for the first time
       |
       v
Cloud-Init reads cloud-init.yaml
       |
       +--> Refresh package index and upgrade packages
       |
       +--> Install NGINX
       |
       +--> Write /var/www/html/index.html
       |
       +--> Enable and restart NGINX
       |
       v
NGINX serves the custom page on TCP port 80
       |
       v
Browser opens http://<PUBLIC-IP>
```

## 9. Troubleshooting

### Website times out

Check: - The VM has a public IP. - The VM's network security group
allows inbound TCP `80`. - Cloud-Init has completed. - NGINX is running.

Commands:

``` powershell
az vm show -d -g CloudInit-RG -n cloudinit-vm01 --query "{powerState:powerState,publicIps:publicIps}" -o table
az vm open-port -g CloudInit-RG -n cloudinit-vm01 --port 80
```

Inside Ubuntu:

``` bash
sudo systemctl status nginx --no-pager
sudo ss -lntp | grep ':80'
```

### Cloud-Init did not complete

``` bash
sudo cloud-init status --long
sudo journalctl -u cloud-init -u cloud-final --no-pager
sudo tail -n 150 /var/log/cloud-init-output.log
```

Check YAML indentation and confirm that the complete HTML content is
nested beneath `content: |`.

### NGINX is installed but the default page appears

Check that Cloud-Init wrote the expected file:

``` bash
sudo head -n 20 /var/www/html/index.html
```

You can restart NGINX after correcting the file:

``` bash
sudo systemctl restart nginx
```

### SSH connection fails

Confirm that the VM is running and that inbound TCP `22` is permitted by
its NSG. The practical opens port `80`; it does not explicitly add a new
SSH rule. Azure VM creation normally creates an SSH rule when using the
Linux VM defaults, but verify the effective NSG rules if SSH is
unavailable.

## 10. Important Cloud-Init concepts and gotchas

-   **First boot:** Azure supplies custom data to the VM, and Cloud-Init
    processes it during initial boot.
-   **Not every restart reruns the configuration:** A normal VM restart
    does not ordinarily rerun once-per-instance Cloud-Init modules.
-   **Custom data is not a secret store:** Do not put passwords, private
    keys, tokens or connection strings in Cloud-Init user data. Treat it
    as configuration data that may be accessible to privileged users and
    through VM provisioning metadata.
-   **Provisioning timing:** Azure reporting that VM creation completed
    does not necessarily mean every application-level setup step has
    finished.
-   **Idempotency:** Design provisioning commands so that rerunning or
    rebuilding the environment does not cause unwanted side effects.
-   **Network access:** A running NGINX service is not enough; the NSG
    and guest firewall must also permit inbound HTTP traffic.
-   **Cost:** Azure resources can continue to incur charges while
    allocated. Delete the resource group after the lab if you no longer
    need it.

## 11. Cleanup

When you have finished the practical, delete the resource group and all
resources created inside it:

``` powershell
az group delete --name CloudInit-RG --yes --no-wait
```

Verify deletion:

``` powershell
az group exists --name CloudInit-RG
```

The result should eventually be `false`.

------------------------------------------------------------------------

## Practical outcome

You have demonstrated infrastructure provisioning with Azure CLI and
guest-OS configuration with Cloud-Init: one PowerShell command creates
the Azure VM, while Cloud-Init installs and configures NGINX and deploys
the web page automatically.
