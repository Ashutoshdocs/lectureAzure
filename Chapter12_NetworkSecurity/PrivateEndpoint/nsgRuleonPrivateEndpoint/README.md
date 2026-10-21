# Azure Lab: Private Endpoint vs NSG

**An Azure VM serves `index.html` that it pulls from a Storage Account over a Private Endpoint — and we use it to prove how NSGs apply to Private Endpoints.**

> **What this lab proves**
>
> An NSG on a Private Endpoint's subnet is **not enforced** on traffic *to* the Private Endpoint while the subnet setting **Private Endpoint Network Policies** is `Disabled`.
> Set it to `Enabled` (or `NetworkSecurityGroupEnabled`) and the **same NSG rule** starts blocking traffic.

---

## Contents

1. [Architecture](#1-architecture)
2. [NSG / port rules](#2-nsg--port-rules)
3. [Prerequisites](#3-prerequisites)
4. [Part A — Build the lab](#part-a--build-the-lab) (Steps 1–8)
5. [Part B — The proof](#part-b--the-proof) (Tests 0–5)
6. [Notes and troubleshooting](#notes-and-troubleshooting)
7. [Cleanup](#cleanup)
8. [Appendix — One-shot VM setup script](#appendix--one-shot-vm-setup-script)

---

## 1. Architecture

```
                         Internet
                            │  TCP 80 (HTTP)   TCP 22 (SSH, your IP only)
                            ▼
┌───────────────────── VNet 10.0.0.0/16 ─────────────────────────────┐
│                                                                    │
│  snet-vm 10.0.1.0/24  (nsg-vm)        snet-pe 10.0.2.0/24 (nsg-pe) │
│  ┌──────────────────────────┐         ┌──────────────────────────┐ │
│  │ vm-web (Ubuntu + nginx)  │  HTTPS  │ pe-blob  (private IP,    │ │
│  │ managed identity         │ ──443──▶│ e.g. 10.0.2.4)           │ │
│  │ serves index.html on :80 │         └────────────┬─────────────┘ │
│  └──────────────────────────┘                      │ Private Link  │
│                                                    ▼               │
│  Private DNS zone: privatelink.blob.core.windows.net (VNet-linked) │
└────────────────────────────────────────────────────┼───────────────┘
                                                     ▼
                              Storage Account (public network access DISABLED)
                              container "web" → index.html
```

**Flow**

1. `index.html` is stored as a blob in container `web`.
2. Public network access on the Storage Account is **disabled** — the Private Endpoint is the only way in.
3. The VM resolves `<account>.blob.core.windows.net` → private IP via the Private DNS zone.
4. The VM gets a token from its **managed identity**, downloads `index.html` over HTTPS (443), and nginx serves it on port **80**.

---

## 2. NSG / port rules

### `nsg-vm` (on `snet-vm`)

| Dir | Priority | Name | Source | Dest | Port | Proto | Action | Why |
|---|---|---|---|---|---|---|---|---|
| In | 100 | Allow-SSH-MyIP | Your public IP | Any | 22 | TCP | Allow | Admin SSH |
| In | 110 | Allow-HTTP | Internet (or your IP) | Any | 80 | TCP | Allow | Browse the site |
| Out | 65000 (default) | AllowVnetOutBound | VirtualNetwork | VirtualNetwork | Any | Any | Allow | VM → PE on 443 |
| Out | 65001 (default) | AllowInternetOutBound | Any | Internet | Any | Any | Allow | `apt install` |

> The managed-identity token comes from IMDS (`169.254.169.254:80`). NSGs don't filter IMDS, so no rule is needed.

### `nsg-pe` (on `snet-pe`)

| Dir | Priority | Name | Source | Dest | Port | Proto | Action | Why |
|---|---|---|---|---|---|---|---|---|
| In | 65000 (default) | AllowVnetInBound | VirtualNetwork | VirtualNetwork | Any | Any | Allow | VM → PE allowed by default |
| In | 100 | **Deny-VM-to-PE-443** *(test only)* | 10.0.1.0/24 | 10.0.2.0/24 | 443 | TCP | Deny | Added during the proof |

**Locked-down production version** (only effective once PE network policies are enabled):

| Priority | Source | Destination | Port | Action |
|---|---|---|---|---|
| 100 | 10.0.1.0/24 (snet-vm) | 10.0.2.0/24 | 443 | Allow |
| 4000 | Any | Any | Any | Deny |

---

## 3. Prerequisites

- Azure CLI signed in (`az login`)
- Permission to create resource groups, VNets, VMs, Storage accounts and **role assignments**
- Bash (Cloud Shell, Linux, macOS or WSL)

---

## Part A — Build the lab

### Step 1 — Variables

```bash
RG=rg-pe-nsg-demo
LOC=centralindia
VNET=vnet-demo
SA=stpedemo$RANDOM                       # globally unique, 3-24 lowercase letters/digits
VM=vm-web
MYIP=$(curl -s -4 https://ifconfig.me)   # -4 forces IPv4 (NSG rule needs it)

echo "Storage account: $SA   My IP: $MYIP"
```

> If you open a new terminal later, re-run this block — but **hard-code `SA`** to the value printed above, or `$RANDOM` will give you a different name.

### Step 2 — Resource group, VNet, subnets

```bash
az group create -n $RG -l $LOC

az network vnet create -g $RG -n $VNET \
  --address-prefix 10.0.0.0/16 \
  --subnet-name snet-vm --subnet-prefix 10.0.1.0/24

# PE subnet with network policies explicitly DISABLED (the behaviour we prove first)
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-pe \
  --address-prefixes 10.0.2.0/24 \
  --private-endpoint-network-policies Disabled
```

### Step 3 — NSGs and rules

```bash
# --- VM subnet NSG ---
az network nsg create -g $RG -n nsg-vm

az network nsg rule create -g $RG --nsg-name nsg-vm -n Allow-SSH-MyIP \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes $MYIP --destination-port-ranges 22

az network nsg rule create -g $RG --nsg-name nsg-vm -n Allow-HTTP \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 80

az network vnet subnet update -g $RG --vnet-name $VNET -n snet-vm \
  --network-security-group nsg-vm

# --- PE subnet NSG (no custom rules yet) ---
az network nsg create -g $RG -n nsg-pe

az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
  --network-security-group nsg-pe
```

### Step 4 — Storage account and `index.html`

Create the page locally:

```bash
cat > index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Private Endpoint Demo</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 60px auto; padding: 0 16px; }
    .ok { color: #0a7d32; }
    code { background: #f2f2f2; padding: 2px 6px; border-radius: 4px; }
  </style>
</head>
<body>
  <h1 class="ok">✅ Served from Azure Blob Storage via Private Endpoint</h1>
  <p>This page lives in a Storage Account with <strong>public network access disabled</strong>.</p>
  <p>The VM downloaded it over <code>HTTPS :443</code> to the Private Endpoint using its managed identity,
     and nginx is serving it on <code>:80</code>.</p>
</body>
</html>
EOF
```

Create the account, upload **while public access is still on**, then lock it down:

```bash
az storage account create -g $RG -n $SA -l $LOC \
  --sku Standard_LRS --kind StorageV2 \
  --allow-blob-public-access false --min-tls-version TLS1_2

KEY=$(az storage account keys list -g $RG -n $SA --query "[0].value" -o tsv)

az storage container create --account-name $SA --account-key $KEY -n web

az storage blob upload --account-name $SA --account-key $KEY \
  -c web -f index.html -n index.html --overwrite

# From now on, only the Private Endpoint can reach the account
az storage account update -g $RG -n $SA --public-network-access Disabled

SA_ID=$(az storage account show -g $RG -n $SA --query id -o tsv)
```

> If your subscription blocks shared-key access by policy, give yourself **Storage Blob Data Contributor** on the account and use `--auth-mode login` instead of `--account-key`.

### Step 5 — Private Endpoint and Private DNS

```bash
az network private-endpoint create -g $RG -n pe-blob \
  --vnet-name $VNET --subnet snet-pe \
  --private-connection-resource-id $SA_ID \
  --group-id blob --connection-name pe-blob-conn

az network private-dns zone create -g $RG -n privatelink.blob.core.windows.net

az network private-dns link vnet create -g $RG \
  -z privatelink.blob.core.windows.net -n link-$VNET \
  -v $VNET -e false

az network private-endpoint dns-zone-group create -g $RG \
  --endpoint-name pe-blob -n default \
  --private-dns-zone privatelink.blob.core.windows.net --zone-name blob

# Get the PE's private IP from its NIC
PE_NIC=$(az network private-endpoint show -g $RG -n pe-blob \
  --query "networkInterfaces[0].id" -o tsv)
PE_IP=$(az network nic show --ids $PE_NIC \
  --query "ipConfigurations[0].privateIPAddress" -o tsv)

echo "Private Endpoint IP: $PE_IP"
```

### Step 6 — VM with managed identity

```bash
az vm create -g $RG -n $VM \
  --image Ubuntu2204 --size Standard_B1s \
  --vnet-name $VNET --subnet snet-vm --nsg "" \
  --public-ip-sku Standard \
  --admin-username azureuser --generate-ssh-keys \
  --assign-identity

PRINCIPAL=$(az vm show -g $RG -n $VM --query identity.principalId -o tsv)

az role assignment create \
  --assignee-object-id $PRINCIPAL --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" --scope $SA_ID

VM_IP=$(az vm show -d -g $RG -n $VM --query publicIps -o tsv)
echo "VM public IP: $VM_IP   Storage account: $SA   PE IP: $PE_IP"
```

> - `--nsg ""` stops the CLI from creating a NIC-level NSG, so only the subnet NSG `nsg-vm` applies.
> - Role assignments can take **2–5 minutes** to take effect. A `403` in Step 7 right after this usually just means "wait".

### Step 7 — Configure the VM

SSH in:

```bash
ssh azureuser@$VM_IP
```

On the VM — set your storage account name on the first line, then paste the rest:

```bash
SA=<storage-account-name>     # value of $SA from Step 1

sudo apt-get update && sudo apt-get install -y nginx jq netcat-openbsd

sudo tee /usr/local/bin/sync-index.sh > /dev/null <<EOF
#!/bin/bash
SA="$SA"
EOF

sudo tee -a /usr/local/bin/sync-index.sh > /dev/null <<'EOF'
TMP=$(mktemp)

TOKEN=$(curl -s --max-time 5 -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
  | jq -r '.access_token // empty')

if [[ -z "$TOKEN" ]]; then
  echo "$(date -Is) FAILED: could not get managed identity token"; exit 1
fi

if curl -sf --max-time 15 \
     -H "Authorization: Bearer $TOKEN" \
     -H "x-ms-version: 2020-04-08" \
     "https://$SA.blob.core.windows.net/web/index.html" -o "$TMP"; then
  install -m 644 "$TMP" /var/www/html/index.html
  rm -f "$TMP"
  echo "$(date -Is) SUCCESS: index.html downloaded via Private Endpoint"
else
  rm -f "$TMP"
  echo "$(date -Is) FAILED: could not reach storage (blocked, timed out, or no RBAC)"
  exit 1
fi
EOF

sudo chmod +x /usr/local/bin/sync-index.sh
sudo /usr/local/bin/sync-index.sh
```

Optional — keep the page in sync every 5 minutes:

```bash
echo "*/5 * * * * root /usr/local/bin/sync-index.sh >> /var/log/sync-index.log 2>&1" \
  | sudo tee /etc/cron.d/sync-index
```

Open `http://<VM_IP>` in a browser — you should see the demo page.

> Prefer one command? See the [Appendix](#appendix--one-shot-vm-setup-script) for a script that does Step 7 (plus checks) for you.

### Step 8 — Verify traffic really uses the Private Endpoint

**On the VM:**

```bash
nslookup <storage-account-name>.blob.core.windows.net
```

Expected: CNAME to `<account>.privatelink.blob.core.windows.net`, resolving to **10.0.2.x** (the PE IP) — not a public IP.

**From your laptop (outside the VNet):**

```bash
curl -I https://<storage-account-name>.blob.core.windows.net/web/index.html
```

Expected: **HTTP 403** — public network access is disabled, so storage is reachable only privately.

---

## Part B — The proof

Use two terminals:

- **Terminal 1:** SSH'd into the VM
- **Terminal 2:** Azure CLI with the Step 1 variables loaded

### Test 0 — Check the current setting *(Terminal 2)*

```bash
az network vnet subnet show -g $RG --vnet-name $VNET -n snet-pe \
  --query privateEndpointNetworkPolicies -o tsv
```

Expected: `Disabled`

### Test 1 — Baseline: access works *(Terminal 1)*

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

Expected: `SUCCESS`, and `nc` reports `succeeded!`

### Test 2 — Add a DENY rule on the PE subnet's NSG

*Terminal 2:*

```bash
az network nsg rule create -g $RG --nsg-name nsg-pe -n Deny-VM-to-PE-443 \
  --priority 100 --direction Inbound --access Deny --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-address-prefixes 10.0.2.0/24 \
  --destination-port-ranges 443
```

Priority 100 is evaluated before `AllowVnetInBound` (65000), so on a normal VM NIC this **would** block the traffic.

Wait ~1 minute. *Terminal 1:*

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

**Expected: still `SUCCESS`.**

✅ **Proof, part 1:** the deny rule exists and the NSG is attached to the subnet, but the Private Endpoint ignores it while network policies are `Disabled`.

### Test 3 — Enable Private Endpoint Network Policies

*Terminal 2:*

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
  --private-endpoint-network-policies Enabled
```

| Value | Effect |
|---|---|
| `Disabled` | Neither NSG nor UDR applies to Private Endpoints |
| `NetworkSecurityGroupEnabled` | Only NSG applies |
| `RouteTableEnabled` | Only UDR applies |
| `Enabled` | Both NSG and UDR apply |

Wait **2–5 minutes**. *Terminal 1:*

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

**Expected: `FAILED`, and `nc` times out.**

✅ **Proof, part 2:** the same, unchanged NSG rule now blocks the traffic. The website keeps serving the last downloaded copy, but new syncs fail.

### Test 4 — Show the NSG rule is the cause

*Terminal 2:*

```bash
az network nsg rule delete -g $RG --nsg-name nsg-pe -n Deny-VM-to-PE-443
```

Wait ~1 minute. *Terminal 1:*

```bash
sudo /usr/local/bin/sync-index.sh
```

**Expected: `SUCCESS` again.** Policies are still `Enabled`; now the default `AllowVnetInBound` rule lets the traffic through.

### Test 5 (optional) — Toggle back to Disabled with the deny rule present

1. Re-create the deny rule from Test 2 and confirm the sync **fails** (policies still `Enabled`).
2. Disable policies:

   ```bash
   az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
     --private-endpoint-network-policies Disabled
   ```

3. After a few minutes, `sync-index.sh` **succeeds** even though the deny rule is still there.

This confirms the subnet toggle alone decides whether the PE-side NSG applies.

### Results summary

| Test | PE network policies | Deny rule on `nsg-pe` | Result |
|---|---|---|---|
| 1 | Disabled | No | ✅ Works |
| 2 | Disabled | Yes | ✅ Works → **NSG ignored** |
| 3 | Enabled | Yes | ❌ Blocked → **NSG enforced** |
| 4 | Enabled | No | ✅ Works (default allow) |
| 5 | Disabled | Yes | ✅ Works → NSG ignored again |

---

## Notes and troubleshooting

- **The source-side NSG always applies.** An outbound deny on `nsg-vm` blocks VM → PE traffic regardless of the PE subnet setting. The toggle only controls the NSG on the **Private Endpoint's** subnet.
- **Test with new connections.** An already-open TCP session can survive a rule change briefly.
- **Changes aren't instant.** NSG rules: ~1 min. Subnet policy toggle: 2–5 min.
- **Test by IP and by name.** `nc` to the PE IP isolates network issues from DNS issues.

| Symptom | Likely cause |
|---|---|
| `nslookup` returns a public IP | Private DNS zone not linked to the VNet, or zone group missing (Step 5) |
| `FAILED` with HTTP 403 right after setup | Role assignment still propagating — wait a few minutes |
| `FAILED: could not get managed identity token` | VM created without `--assign-identity` |
| Browser can't reach the site | `Allow-HTTP` rule missing, or nginx not running (`systemctl status nginx`) |
| Can't SSH | Your public IP changed — update `Allow-SSH-MyIP` |

---

## Cleanup

```bash
az group delete -n $RG --yes --no-wait
```

---

## Appendix — One-shot VM setup script

`setup-private-storage-web.sh` is an alternative to Step 7. Copy it to the VM and run:

```bash
scp setup-private-storage-web.sh azureuser@$VM_IP:~
ssh azureuser@$VM_IP
sudo bash setup-private-storage-web.sh
```

Or non-interactively:

```bash
sudo STORAGE_ACCOUNT=<sa-name> CONTAINER_NAME=web PRIVATE_IP=<pe-ip> WEB_PORT=80 \
  bash setup-private-storage-web.sh
```

What it does:

1. Installs nginx, curl and the Azure CLI
2. Checks that the blob hostname resolves to the PE IP through Private DNS — and only if it doesn't, adds an `/etc/hosts` override and warns you
3. Verifies managed-identity sign-in
4. Installs `/usr/local/bin/sync-index.sh` (same name as Step 7, so the Part B tests work unchanged) and downloads `index.html`, retrying while RBAC propagates
5. Schedules the sync every 5 minutes
6. Configures nginx on `WEB_PORT` (default **80**) with a `/health` endpoint
7. Verifies the site locally

> If you choose a port other than 80, add a matching inbound rule to `nsg-vm`.
