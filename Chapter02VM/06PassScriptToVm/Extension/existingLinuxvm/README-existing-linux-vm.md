# Run an Existing Bash Script on an Existing Azure Linux VM

## Azure Custom Script Extension for Linux

This practical demonstrates how to run a Bash script that is already stored in an Azure Storage Account on an Ubuntu VM that has already been created.

**Important:** This workflow does not create a VM and does not upload the script again.

## 1. Existing resources

| Resource | Status |
|---|---|
| Azure Storage Account | Already created |
| Blob container | Already created (example: `scripts`) |
| Bash script | Already uploaded (example: `setup-nginx.sh`) |
| Ubuntu Linux VM | Already created |
| Custom Script Extension | We will install it now |

The example script installs nginx and publishes a simple web page.

## 2. How it works

```text
Azure Storage Account
  |
  +-- Blob container: scripts
        |
        +-- setup-nginx.sh
                 |
                 | HTTPS download (Blob URL + read-only SAS)
                 v
        Existing Ubuntu VM
                 |
                 v
        Custom Script Extension for Linux
                 |
                 v
        bash setup-nginx.sh
                 |
                 v
        nginx installed and started
                 |
                 v
        http://<VM-Public-IP>
```

The Azure Linux VM agent downloads the file and executes the command. The Custom Script Extension normally runs the command with elevated privileges (root).

## 3. Before you start

You need:

- The resource group name containing your existing VM.
- The existing Linux VM name.
- The storage account name.
- The blob container name.
- The exact blob filename, including uppercase/lowercase.
- A way for the VM to reach Azure Storage and Ubuntu package repositories over HTTPS.

Make sure the VM has outbound internet/network access so `apt-get update` and `apt-get install nginx` can work.

## 4. Get the script's Blob URL and SAS token

The extension must be able to read the blob. For a private container, use a **read-only, time-limited SAS URL**.

### Azure Portal method

1. Open **Storage accounts** and select your existing storage account.
2. Go to **Data storage → Containers**.
3. Open the container that contains `setup-nginx.sh`.
4. Select the `setup-nginx.sh` blob.
5. Open **Generate SAS** (the label/location can vary slightly in the portal).
6. Grant only **Read** permission.
7. Set an expiry long enough for the practical, using your organization's policy.
8. Generate the SAS token/URL.
9. Copy the complete URL. It should look similar to:

```text
https://<storage-account>.blob.core.windows.net/<container>/setup-nginx.sh?<SAS-token>
```

Treat this URL like a password while it is valid. Do not commit it to Git or share it publicly. Revoke/allow it to expire after the practical.

If the blob is intentionally public, its HTTPS blob URL can be used without a SAS token. Do not make a private container public just to run this demo.

## 5. Run it from Azure Portal (no VM recreation)

1. Open **Virtual machines**.
2. Select your **existing Ubuntu VM**.
3. Open **Settings → Extensions + applications**.
4. Select **+ Add**.
5. Choose **Custom Script for Linux** (publisher: Microsoft.Azure.Extensions; extension name: CustomScript).
6. In the configuration, provide the complete script Blob URL in **Script files**.
7. Set the command to:

```bash
bash setup-nginx.sh
```

8. Select **Review + create** / **Create** and wait for provisioning to finish.

Portal labels can vary by blade/version. If the portal form does not accept a SAS URL in Script files, use the Azure CLI method below; it explicitly passes the SAS URL in protected settings.

## 6. Run it using Azure CLI (recommended repeatable method)

Run these commands from Azure Cloud Shell, or from a computer with Azure CLI installed and signed in.

### Step 1 — Sign in and select the subscription

```bash
az login
az account set --subscription "<SUBSCRIPTION-ID-OR-NAME>"
```

### Step 2 — Set your existing resource names

Replace the example values with your real values:

```bash
RG="<RESOURCE-GROUP-NAME>"
VM="<EXISTING-LINUX-VM-NAME>"
BLOB_URL="https://<storage-account>.blob.core.windows.net/<container>/setup-nginx.sh?<SAS-token>"
```

Keep the complete SAS URL inside the quotes. Do not add extra quotes or spaces inside the URL.

### Step 3 — Create protected settings

Create a file named `protected-settings.json` on the machine where you run Azure CLI:

```json
{
  "fileUris": [
    "https://<storage-account>.blob.core.windows.net/<container>/setup-nginx.sh?<SAS-token>"
  ],
  "commandToExecute": "bash setup-nginx.sh"
}
```

Replace the URL with the complete Blob SAS URL you generated. This file contains a credential-bearing URL: keep it private and delete it securely when you finish.

### Step 4 — Install the extension on the existing VM

Run:

```bash
az vm extension set \
  --resource-group "$RG" \
  --vm-name "$VM" \
  --publisher Microsoft.Azure.Extensions \
  --name CustomScript \
  --version 2.1 \
  --protected-settings @protected-settings.json
```

This command targets the existing VM. It does not create or rebuild the VM.

### Step 5 — Check extension provisioning status

```bash
az vm extension list \
  --resource-group "$RG" \
  --vm-name "$VM" \
  --output table
```

For detailed instance status:

```bash
az vm get-instance-view \
  --resource-group "$RG" \
  --name "$VM" \
  --query "instanceView.extensions" \
  --output json
```

Look for the CustomScript extension and a successful provisioning/status message. Allow a few minutes for package installation.

## 7. Verify the website

1. Open the VM's **Overview** page and copy its Public IP address.
2. Confirm an inbound NSG rule allows **TCP port 80 (HTTP)** from the source range appropriate for your demo.
3. Open this address in a browser:

```text
http://<VM-PUBLIC-IP>
```

You should see the page titled **nginx is running**.

You can also SSH to the VM and run:

```bash
sudo systemctl status nginx
curl -I http://localhost
```

## 8. Run again after changing the script

If you update the blob, do not assume that the extension will automatically rerun just because the blob contents changed. The extension runs when its configuration is applied.

For a simple repeatable demo, remove the existing extension and add it again with the updated script URL/settings:

```bash
az vm extension delete \
  --resource-group "$RG" \
  --vm-name "$VM" \
  --name CustomScript
```

Then run the `az vm extension set` command from Step 4 again.

Use a fresh SAS URL if the previous SAS has expired. If you reuse the same filename, consider changing the blob name (for example, `setup-nginx-v2.sh`) to avoid confusion about which version was downloaded.

## 9. Troubleshooting

### Extension failed

Check the extension status in **VM → Extensions + applications**. On the VM, inspect:

```bash
sudo tail -n 200 /var/log/azure/custom-script/handler.log
sudo find /var/lib/waagent/custom-script/download -type f \
  \( -name stdout -o -name stderr \) -print
```

Read the `stdout` and `stderr` files in the relevant numbered download directory.

### SAS / download error

- Confirm the SAS URL is complete and has not expired.
- Confirm it grants **Read** permission.
- Confirm the storage account firewall/network rules allow the VM's network path.
- Confirm the container and blob names are correct and case-sensitive.
- Do not paste a SAS token into public logs, screenshots, Git repositories, or chat.

### nginx is installed but the page does not open

```bash
sudo systemctl status nginx
sudo ss -lntp | grep ':80'
curl -I http://localhost
```

Also check the VM's Network Security Group for an inbound TCP 80 rule, and any guest OS firewall rules.

### Script fails with `$'\r': command not found`

The script likely has Windows CRLF line endings. Save it with **LF** line endings and upload the corrected file.

### Package installation fails

Check DNS and outbound connectivity from the VM to Ubuntu package repositories. The VM needs outbound connectivity for `apt-get update` and `apt-get install`.

## 10. Alternative: Run Command (without installing an extension)

For a one-time test, you can use **VM → Operations → Run command → RunShellScript** and paste the script content. This is useful for troubleshooting or a quick run.

However, when the learning objective is **Azure Custom Script Extension for Linux**, use the extension workflow in Sections 5 or 6.

## 11. Clean up

- Delete the Custom Script Extension if it is no longer needed.
- Allow the short-lived SAS token to expire or revoke it according to your storage access process.
- Remove the local `protected-settings.json` file securely.
- Remove the demo NSG rule if it is no longer required.

## AZ-104 learning points

- A VM extension can be installed **after** a VM has been created.
- Linux uses **Custom Script for Linux** (`Microsoft.Azure.Extensions`, `CustomScript`).
- The extension can download scripts from Azure Storage or another reachable HTTPS endpoint.
- A private blob needs an authorized download method, such as a read-only SAS URL.
- The extension executes the configured command on the VM; it does not create the VM.
- Use **Run Command** for a one-time command, and the Custom Script Extension when demonstrating VM extension-based configuration.

---

**Practical result:** An already-created Ubuntu VM downloads `setup-nginx.sh` from the existing Storage Account, executes it, installs nginx, and serves the demo page.
