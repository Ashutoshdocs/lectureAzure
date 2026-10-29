# Azure Run Command — Nginx Demo on an Existing VM

## Objective

This practical demonstrates **Azure VM Run Command** using Azure CLI.

An **already-running Azure Ubuntu VM** will be remotely configured to:

1. Install Nginx.
2. Create a beautiful HTML webpage.
3. Start and enable Nginx.
4. Verify the web server.
5. Access the webpage from a browser.

The webpage displays:

> **Page deployed via az vm run-command**

---

# Architecture

```text
Your Laptop / Azure Cloud Shell
             |
             | az vm run-command invoke
             v
       Azure VM Agent
             |
             v
       Linux VM
             |
      +------+------+
      |             |
   apt install   index.html
      |             |
      +------+------+
             |
           Nginx
             |
           Port 80
             |
          Browser
```

---

# 1. Prerequisites

You need:

- An existing Azure VM
- Ubuntu Linux VM
- Azure CLI
- Permission to execute commands on the VM
- VM should be running
- Port 80 allowed in the VM's NSG for browser testing

Login:

```bash
az login
```

Check the subscription:

```bash
az account show
```

If required:

```bash
az account set --subscription "<SUBSCRIPTION-ID-OR-NAME>"
```

---

# 2. Identify the VM

Set variables:

```bash
RG_NAME="<RESOURCE-GROUP>"
VM_NAME="<VM-NAME>"
```

Example:

```bash
RG_NAME="rg-demo"
VM_NAME="vm-web01"
```

Check the VM:

```bash
az vm show -g "$RG_NAME" -n "$VM_NAME" -o table
```

Check its power state:

```bash
az vm get-instance-view \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --query instanceView.statuses[1].displayStatus \
  -o tsv
```

Expected:

```text
VM running
```

---

# 3. Understand Azure Run Command

Azure Run Command allows you to execute scripts **inside an Azure VM remotely**.

The important command is:

```bash
az vm run-command invoke
```

The execution flow is:

```text
az CLI
   |
   v
Azure control plane
   |
   v
VM Run Command
   |
   v
Azure VM Agent
   |
   v
Command executes inside Linux VM
```

You do **not** need to SSH into the VM for this demo.

---

# 4. Execute the Demo

The supplied file is:

```text
deploy-nginx.sh
```

Run:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts @deploy-nginx.sh
```

Azure sends the script to the VM.

The script:

```text
apt-get update
       ↓
Install nginx
       ↓
Create index.html
       ↓
Enable nginx
       ↓
Restart nginx
       ↓
Test nginx
```

---

# 5. What Happens Inside the VM?

## Step 1 — Package installation

The script executes:

```bash
apt-get update -y
apt-get install -y nginx
```

Nginx is installed inside the VM.

---

## Step 2 — Webpage creation

The script creates:

```text
/var/www/html/index.html
```

This becomes the default webpage served by Nginx.

---

## Step 3 — Start Nginx

The script executes:

```bash
systemctl enable nginx
systemctl restart nginx
```

So Nginx:

- starts now
- starts automatically after reboot

---

# 6. Verify Run Command Output

The `az vm run-command invoke` command returns the command execution result.

Look for:

```text
Azure Run Command Nginx demo completed successfully.
```

and:

```text
active
```

and:

```text
HTTP/1.1 200 OK
```

---

# 7. Verify Nginx from Azure CLI

Check the VM service using Run Command:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "systemctl is-active nginx"
```

Expected:

```text
active
```

---

# 8. Verify the Webpage from Inside the VM

Run:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "curl -I http://localhost"
```

Expected:

```text
HTTP/1.1 200 OK
```

You can also check the page content:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "curl -s http://localhost | grep 'Page deployed'"
```

---

# 9. Get the VM Public IP

Run:

```bash
PUBLIC_IP=$(az vm show -d \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --query publicIps \
  -o tsv)

echo "$PUBLIC_IP"
```

Then open:

```text
http://<PUBLIC-IP>
```

Example:

```text
http://20.x.x.x
```

You should see:

# ☁ Page deployed via az vm run-command

---

# 10. Azure NSG — Allow Port 80

If the webpage cannot be reached from the browser, check the NSG.

Find the NIC:

```bash
NIC_ID=$(az vm show \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --query 'networkProfile.networkInterfaces[0].id' \
  -o tsv)

echo "$NIC_ID"
```

Get the NSG:

```bash
az network nic show \
  --ids "$NIC_ID" \
  --query 'networkSecurityGroup.id' \
  -o tsv
```

If required, create an HTTP rule on the NSG:

```bash
NSG_NAME="<NSG-NAME>"
```

Then:

```bash
az network nsg rule create \
  -g "$RG_NAME" \
  --nsg-name "$NSG_NAME" \
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

---

# 11. Important Difference: Run Command vs Cloud-Init

This demo is useful to compare the two approaches.

| Feature | Cloud-Init | Azure Run Command |
|---|---|---|
| Typical use | VM initialization/configuration | Remote execution on existing VM |
| New VM | Very common | Also possible |
| Existing VM | Can be explicitly executed | Designed for remote commands |
| Requires SSH | No | No |
| Azure CLI | Not required inside config | `az vm run-command` |
| Execution | Cloud-init modules | Azure VM Agent |
| Good for | Bootstrap/configuration | Repair, troubleshooting, deployment |

### Simple teaching statement

**Cloud-init:**

```text
"Configure this VM according to this initialization configuration."
```

**Run Command:**

```text
"Execute this command/script inside this existing Azure VM."
```

---

# 12. Demonstrate That SSH Is Not Required

For this practical, you can intentionally avoid:

```bash
ssh azureuser@<VM-IP>
```

Instead:

```bash
az vm run-command invoke ...
```

Azure communicates with the VM through the **Azure VM Agent**.

Conceptually:

```text
Your machine
     |
     | Azure API
     v
Azure
     |
     | Run Command
     v
Azure VM Agent
     |
     v
Linux shell
```

---

# 13. Useful Troubleshooting Commands

Check VM status:

```bash
az vm get-instance-view \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --query instanceView.statuses \
  -o table
```

Check Nginx:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "systemctl status nginx --no-pager"
```

Check port 80:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "ss -lntp | grep ':80'"
```

Check webpage:

```bash
az vm run-command invoke \
  -g "$RG_NAME" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "curl -s http://localhost"
```

---

# 14. Demo Sequence for Teaching

Use this sequence in a classroom.

### Step 1

Show an already-running VM:

```text
Azure VM
Status: Running
```

### Step 2

Explain:

```text
We will NOT SSH into the VM.
```

### Step 3

Run:

```bash
az vm run-command invoke
```

### Step 4

Azure sends the script through:

```text
Azure
  ↓
VM Agent
  ↓
Linux
```

### Step 5

The script installs:

```text
Nginx
```

### Step 6

The script creates:

```text
/var/www/html/index.html
```

### Step 7

Nginx serves:

```text
HTTP :80
```

### Step 8

Open:

```text
http://<PUBLIC-IP>
```

---

# 15. Key Learning

The important concept is:

```text
Azure Run Command
       ↓
Remote command execution
       ↓
Existing VM
       ↓
No SSH required
       ↓
Execute shell script
       ↓
Configure / troubleshoot / deploy
```

The VM must have the Azure VM Agent functioning so Azure can deliver the Run Command operation.

---

# Files

```text
az_invoke_nginx_demo/
├── deploy-nginx.sh
└── README.md
```

`deploy-nginx.sh` is the script sent into the VM by:

```bash
az vm run-command invoke
```
