# Cloud-Init Nginx Demo — Existing Ubuntu VM

## Objective

This demo shows how to use **cloud-init on an already running Ubuntu VM** to:

1. Install Nginx.
2. Create a beautiful HTML webpage.
3. Start and enable Nginx.
4. Verify that the page is being served.
5. Open the page from a browser.

The webpage displays:

> **Page deployed via Cloud-Init**

---

## Architecture

```text
Already Running Ubuntu VM
          |
          | cloud-init configuration
          v
     Install Nginx
          |
          v
 /var/www/html/index.html
          |
          v
     Nginx :80
          |
          v
   Browser → http://VM-IP
```

---

# 1. Prerequisites

The VM should have:

- Ubuntu 20.04 / 22.04 / 24.04
- `sudo` access
- Internet access for installing Nginx
- TCP port **80** allowed in the VM firewall / Azure NSG if the VM is in Azure

Check the OS:

```bash
cat /etc/os-release
```

Check cloud-init:

```bash
cloud-init --version
```

---

# 2. Copy the Cloud-Init File to the VM

Copy `cloud-init.yaml` to the existing VM.

For example:

```bash
scp cloud-init.yaml azureuser@<VM-IP>:/home/azureuser/
```

Or create it directly:

```bash
nano /home/azureuser/cloud-init.yaml
```

Paste the contents of `cloud-init.yaml`.

---

# 3. Validate the Cloud-Init Configuration

Run:

```bash
cloud-init schema --config-file /home/azureuser/cloud-init.yaml
```

Expected result:

```text
Valid cloud-config: /home/azureuser/cloud-init.yaml
```

If your cloud-init version does not support `--config-file`, use:

```bash
cloud-init devel schema --config-file /home/azureuser/cloud-init.yaml
```

---

# 4. Run Cloud-Init on the Existing VM

## Important concept

Normally, cloud-init is most commonly used during the **first boot** of a cloud VM.

This lab is specifically demonstrating how to execute a cloud-init configuration on a VM that is **already running**.

Run the individual cloud-init modules explicitly.

First, install packages:

```bash
sudo cloud-init single --name cc_package_update_upgrade_install --frequency always --file /home/azureuser/cloud-init.yaml
```

Then create the webpage:

```bash
sudo cloud-init single --name cc_write_files --frequency always --file /home/azureuser/cloud-init.yaml
```

Finally execute the commands from `runcmd`:

```bash
sudo cloud-init single --name cc_scripts_user --frequency always --file /home/azureuser/cloud-init.yaml
```

### What happens?

The configuration contains:

```yaml
packages:
  - nginx
```

So cloud-init installs Nginx.

It also contains:

```yaml
write_files:
```

which creates:

```text
/var/www/html/index.html
```

Finally:

```yaml
runcmd:
  - systemctl enable nginx
  - systemctl restart nginx
```

starts Nginx and enables it at boot.

---

# 5. Verify Nginx

Check the package:

```bash
dpkg -l | grep nginx
```

Check the service:

```bash
systemctl status nginx
```

You should see:

```text
Active: active (running)
```

Check port 80:

```bash
sudo ss -lntp | grep ':80'
```

---

# 6. Verify the Webpage Locally

Run:

```bash
curl http://localhost
```

You should see the HTML content containing:

```text
Page deployed via Cloud-Init
```

You can also run:

```bash
curl -I http://localhost
```

Expected:

```text
HTTP/1.1 200 OK
```

---

# 7. Find the VM IP

For Azure:

```bash
az vm show -d \
  -g <RESOURCE-GROUP> \
  -n <VM-NAME> \
  --query publicIps \
  -o tsv
```

Or from the VM:

```bash
hostname -I
```

For a browser test, use the VM's reachable public IP.

Open:

```text
http://<VM-PUBLIC-IP>
```

You should see:

# ☁ Page deployed via Cloud-Init

---

# 8. Azure NSG — Allow HTTP

If this is an Azure VM, make sure TCP port 80 is allowed by the VM's NSG.

Check NSG rules:

```bash
az network nsg rule list \
  -g <RESOURCE-GROUP> \
  --nsg-name <NSG-NAME> \
  -o table
```

If required, create an HTTP rule:

```bash
az network nsg rule create \
  -g <RESOURCE-GROUP> \
  --nsg-name <NSG-NAME> \
  -n Allow-HTTP \
  --priority 100 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes Internet \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 80
```

Then browse to:

```text
http://<VM-PUBLIC-IP>
```

---

# 9. Verify Cloud-Init Execution

Check cloud-init status:

```bash
cloud-init status --long
```

Check the demo log:

```bash
cat /var/log/cloud-init-nginx-demo.log
```

Expected:

```text
Cloud-init Nginx demo completed successfully.
```

View cloud-init logs:

```bash
sudo tail -n 100 /var/log/cloud-init.log
```

Check final-output:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
```

---

# 10. Verify the Generated Webpage

Check that the file exists:

```bash
ls -l /var/www/html/index.html
```

Read it:

```bash
cat /var/www/html/index.html
```

Test through Nginx:

```bash
curl http://localhost/
```

---

# 11. Demo Flow for Teaching

Use this sequence during the practical:

### Step 1 — Start with an existing VM

```text
Ubuntu VM
     |
     | already running
     v
No Nginx / old webpage
```

### Step 2 — Give cloud-init the desired state

```text
cloud-init.yaml
     |
     +--> install nginx
     |
     +--> create index.html
     |
     +--> start nginx
```

### Step 3 — Execute the cloud-init modules

```text
cloud-init
    |
    +--> Package module
    |
    +--> Write-files module
    |
    +--> Scripts/runcmd module
```

### Step 4 — Test

```text
Browser
   |
   | HTTP :80
   v
Nginx
   |
   v
index.html
```

---

# 12. Important Teaching Point

## Cloud-init is configuration, not just a shell script

The file uses cloud-init modules:

```yaml
package_update:
packages:
write_files:
runcmd:
```

Each section represents a desired configuration/action.

For example:

```yaml
packages:
  - nginx
```

means:

> Ensure Nginx is installed.

And:

```yaml
write_files:
```

means:

> Create or update the specified file with the supplied content.

And:

```yaml
runcmd:
```

means:

> Run these commands during the cloud-init final stage.

---

# 13. Existing VM vs New VM

## New VM

For a newly created VM, cloud-init is normally supplied during provisioning.

Conceptually:

```text
VM creation
     |
     v
cloud-init runs automatically
     |
     v
Nginx installed
     |
     v
Website created
```

## Existing VM

For this lab:

```text
Existing VM
     |
     v
Copy cloud-init.yaml
     |
     v
Explicitly execute cloud-init modules
     |
     v
Nginx + webpage
```

This distinction is important when explaining cloud-init.

---

# 14. Cleanup

Remove Nginx if you want to reset the lab:

```bash
sudo systemctl disable --now nginx
```

Then:

```bash
sudo apt remove -y nginx nginx-common
```

Remove the demo page:

```bash
sudo rm -f /var/www/html/index.html
```

---

# 15. Quick Verification Commands

Run these together:

```bash
systemctl is-active nginx
```

```bash
curl -I http://localhost
```

```bash
curl http://localhost | grep "Page deployed"
```

```bash
cloud-init status --long
```

```bash
cat /var/log/cloud-init-nginx-demo.log
```

---

# Expected Result

The browser should display a modern blue gradient page with:

```text
☁ CLOUD-INIT DEMO

Page deployed via Cloud-Init

This Nginx web server and webpage were configured
automatically using a cloud-init configuration
on an already running VM.

VM → Cloud-Init → Nginx → Web Page

✓ Nginx installed | ✓ Website deployed
```

---

## Files

- `cloud-init.yaml` — cloud-init configuration
- `README.md` — complete practical/SOP
