# Azure VM Scale Set Dashboard Demo (Azure CLI)

A self-contained demo that provisions a Linux **Virtual Machine Scale Set** behind a **Standard Load Balancer**, where every instance auto-installs NGINX and serves a live, glassmorphic Azure dashboard. Everything is deployed with the **Azure CLI** — no Bicep or ARM template required.

## What gets deployed

- **Virtual network** (`10.0.0.0/16`) with a single subnet
- **Network security group** allowing inbound HTTP (80) and SSH (22), attached to the subnet
- **Standard public IP** + **Standard Load Balancer** with:
  - a TCP health probe on port 80
  - an HTTP load-balancing rule (80 → 80)
  - an explicit outbound rule (created *before* the VMs boot, so cloud-init can `apt-get` NGINX)
- **VM Scale Set** (Ubuntu 22.04, `Standard_B1s` by default) provisioned by `cloud-init.yaml`

## File overview

| File | Purpose |
|------|---------|
| `deploy.sh` / `deploy.ps1` | Create all resources with the Azure CLI (pick your shell) |
| `autoscale.sh` / `autoscale.ps1` | Add CPU-based scale-out (> 30%) and scale-in (< 15%) rules |
| `cloud-init.yaml` | Installs NGINX and writes the dashboard on first boot |
| `stress.sh` | Burns CPU on an instance to trigger a scale-out |
| `index.html`, `style.css`, `script.js` | The dashboard front end |

The dashboard shows each instance's **real** hostname, region, uptime, and public IP (read from Azure's Instance Metadata Service at boot). The CPU / memory / disk gauges are **simulated** animations — a static NGINX page can't read host metrics without a backend agent. See the note in `script.js` for how to wire in a real metrics endpoint.

## Prerequisites

- [Azure CLI](https://aka.ms/azcli) installed and signed in (`az login`), **or** just use [Azure Cloud Shell](https://shell.azure.com) which has it built in
- An Azure subscription with permission to create resources
- Bash (for the `.sh` scripts) or PowerShell (for the `.ps1` scripts) — the two sets are equivalent

## Quick start

Bash (Linux / macOS / WSL / Cloud Shell):

```bash
az login                         # skip in Cloud Shell
chmod +x deploy.sh autoscale.sh
./deploy.sh                      # prompts for an admin password
./autoscale.sh
```

PowerShell (Windows):

```powershell
az login
./deploy.ps1
./autoscale.ps1
```

Override defaults as needed:

```bash
RG=my-rg LOCATION=eastus INSTANCES=3 VM_SKU=Standard_B2s ./deploy.sh
```
```powershell
./deploy.ps1 -ResourceGroup my-rg -Location eastus -InstanceCount 3 -VmSku Standard_B2s
```

When `deploy` finishes it prints the public IP and dashboard URL. Give cloud-init 2–3 minutes to install NGINX, then open the URL. Refreshing may land you on different instances (different hostnames) as the load balancer distributes traffic.

## Triggering an autoscale event

The simplest way — no SSH needed — is to run a CPU burn on an instance via `run-command`:

```bash
# list instance IDs
az vmss list-instances -g vmss-demo-rg -n vmssdemo-vmss --query "[].instanceId" -o tsv

# burn CPU on instance 0 for 5 minutes
az vmss run-command invoke -g vmss-demo-rg -n vmssdemo-vmss --instance-id 0 \
  --command-id RunShellScript \
  --scripts "for i in 1 2; do (while :; do :; done) & done; sleep 300; kill \$(jobs -p)"
```

Or SSH into an instance (if you added SSH access) and run `./stress.sh 600 2`.

Watch the instance count grow:

```bash
az vmss list-instances -g vmss-demo-rg -n vmssdemo-vmss -o table
```

Autoscale evaluates over a 5-minute window, so allow several minutes for a new instance to appear — and a while after the load stops for it to scale back in.

## Cleanup

Delete everything by removing the resource group:

```bash
az group delete --name vmss-demo-rg --yes --no-wait
```

## Notes

- The demo uses password authentication for simplicity. For anything beyond a demo, switch to SSH keys (`--generate-ssh-keys` / `--ssh-key-values` on `az vmss create`, and drop `--admin-password`).
- The scale set is created in **Uniform** orchestration mode to match the autoscale workflow.
- `Standard_B1s` is inexpensive but small (1 vCPU). If a single stress worker doesn't push CPU past 30%, use a larger SKU or more workers.
- Costs accrue while resources run — remember to clean up.
