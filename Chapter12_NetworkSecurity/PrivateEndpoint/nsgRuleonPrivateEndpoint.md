# Demo: Azure VM serving `index.html` from a Storage Account over a Private Endpoint

This demo builds a private web setup in Azure and proves one specific behaviour:

> **By default, an NSG attached to a Private Endpoint's subnet is NOT enforced on traffic going to that Private Endpoint.**
> It *can* be enforced. You turn that on with the subnet setting **Private Endpoint Network Policies**.

## What gets built

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

Flow:
1. `index.html` is stored as a blob in the Storage Account.
2. Public network access to the Storage Account is disabled. The only way in is the Private Endpoint.
3. The VM resolves `<account>.blob.core.windows.net` to the private IP via the Private DNS zone.
4. The VM uses its managed identity to download `index.html` and nginx serves it on port 80.

---

## Port / NSG rules needed

### `nsg-vm` (attached to `snet-vm`)

| Direction | Priority | Name | Source | Destination | Port | Protocol | Action | Why |
|---|---|---|---|---|---|---|---|---|
| Inbound | 100 | Allow-SSH-MyIP | Your public IP | Any | 22 | TCP | Allow | Admin access to the VM |
| Inbound | 110 | Allow-HTTP | Internet (or your IP) | Any | 80 | TCP | Allow | Users browse the website |
| Outbound | default 65000 | AllowVnetOutBound | VirtualNetwork | VirtualNetwork | Any | Any | Allow | VM → Private Endpoint on 443 (no custom rule needed) |
| Outbound | default 65001 | AllowInternetOutBound | Any | Internet | Any | Any | Allow | `apt install` of nginx/jq |

> The VM also calls the Instance Metadata Service (`169.254.169.254:80`) to get its managed-identity token. NSGs don't block IMDS, so no rule is needed.

### `nsg-pe` (attached to `snet-pe`)

| Direction | Priority | Name | Source | Destination | Port | Protocol | Action | Why |
|---|---|---|---|---|---|---|---|---|
| Inbound | default 65000 | AllowVnetInBound | VirtualNetwork | VirtualNetwork | Any | Any | Allow | VM → Private Endpoint on 443 is allowed by default |
| Inbound | 100 | **Deny-VM-to-PE-443** (test rule) | 10.0.1.0/24 | 10.0.2.0/24 | 443 | TCP | Deny | Added only during the proof to show when NSG is / isn't enforced |

If you want a locked-down production version, add an explicit allow and a catch-all deny instead:

| Priority | Source | Destination | Port | Action |
|---|---|---|---|---|
| 100 | 10.0.1.0/24 (snet-vm) | 10.0.2.0/24 | 443 | Allow |
| 4000 | Any | Any | Any | Deny |

(These only take effect after Private Endpoint Network Policies are enabled on `snet-pe`; see the proof.)

---

## Prerequisites

- Azure CLI (`az`) logged in: `az login`
- A subscription where you can create resource groups, VNets, VMs, Storage and role assignments
- Bash (Cloud Shell, Linux, macOS or WSL)

---

## Step 1 — Set variables

```bash
RG=rg-pe-nsg-demo
LOC=centralindia
VNET=vnet-demo
SA=stpedemo$RANDOM          # must be globally unique, lowercase, 3-24 chars
VM=vm-web
MYIP=$(curl -s https://ifconfig.me)   # your public IP for SSH
echo "Storage account: $SA   My IP: $MYIP"
```

## Step 2 — Resource group, VNet and subnets

```bash
az group create -n $RG -l $LOC

az network vnet create -g $RG -n $VNET \
  --address-prefix 10.0.0.0/16 \
  --subnet-name snet-vm --subnet-prefix 10.0.1.0/24

# PE subnet with network policies DISABLED (this is the default behaviour we want to prove)
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-pe \
  --address-prefixes 10.0.2.0/24 \
  --private-endpoint-network-policies Disabled
```

## Step 3 — NSGs and port rules

```bash
# NSG for the VM subnet
az network nsg create -g $RG -n nsg-vm

az network nsg rule create -g $RG --nsg-name nsg-vm -n Allow-SSH-MyIP \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes $MYIP --destination-port-ranges 22

az network nsg rule create -g $RG --nsg-name nsg-vm -n Allow-HTTP \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 80

az network vnet subnet update -g $RG --vnet-name $VNET -n snet-vm \
  --network-security-group nsg-vm

# NSG for the Private Endpoint subnet (no custom rules yet)
az network nsg create -g $RG -n nsg-pe
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
  --network-security-group nsg-pe
```

## Step 4 — Storage account and `index.html`

Create the page locally:

```bash
cat > index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Private Endpoint Demo</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 15%;">
  <h1>Hello from Azure Storage via Private Endpoint</h1>
  <p>This page was downloaded by the VM over Private Link and served by nginx on port 80.</p>
</body>
</html>
EOF
```

Create the storage account, upload the file **while public access is still on**, then turn public access off:

```bash
az storage account create -g $RG -n $SA -l $LOC \
  --sku Standard_LRS --kind StorageV2 \
  --allow-blob-public-access false --min-tls-version TLS1_2

KEY=$(az storage account keys list -g $RG -n $SA --query "[0].value" -o tsv)

az storage container create --account-name $SA --account-key $KEY -n web
az storage blob upload --account-name $SA --account-key $KEY \
  -c web -f index.html -n index.html --overwrite

# Lock it down: from now on, only the Private Endpoint can reach it
az storage account update -g $RG -n $SA --public-network-access Disabled

SA_ID=$(az storage account show -g $RG -n $SA --query id -o tsv)
```

## Step 5 — Private Endpoint + Private DNS

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

# Note the Private Endpoint IP
PE_IP=$(az network private-endpoint show -g $RG -n pe-blob \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)
echo "Private Endpoint IP: $PE_IP"
```

## Step 6 — VM with managed identity

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
echo "VM public IP: $VM_IP   Storage account: $SA"
```

> `--nsg ""` stops the CLI from creating a NIC-level NSG; the subnet NSG `nsg-vm` is the one that applies.
> Role assignments can take a few minutes to take effect.

## Step 7 — Configure the VM to fetch and host the page

SSH in:

```bash
ssh azureuser@$VM_IP
```

On the VM (replace `<storage-account-name>` with the value of `$SA`):

```bash
sudo apt-get update && sudo apt-get install -y nginx jq

sudo tee /usr/local/bin/sync-index.sh > /dev/null <<'EOF'
#!/bin/bash
SA="<storage-account-name>"
TOKEN=$(curl -s -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
  | jq -r .access_token)

curl -sf --max-time 15 \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-ms-version: 2020-04-08" \
  "https://$SA.blob.core.windows.net/web/index.html" \
  -o /tmp/index.html \
&& sudo mv /tmp/index.html /var/www/html/index.html \
&& echo "SUCCESS: index.html downloaded via Private Endpoint" \
|| echo "FAILED: could not reach storage (blocked or timed out)"
EOF

sudo chmod +x /usr/local/bin/sync-index.sh
sudo /usr/local/bin/sync-index.sh
```

Optional: keep the page in sync every 5 minutes:

```bash
echo "*/5 * * * * root /usr/local/bin/sync-index.sh >> /var/log/sync-index.log 2>&1" \
  | sudo tee /etc/cron.d/sync-index
```

Open `http://<VM_IP>` in your browser. You should see the demo page.

## Step 8 — Verify it really uses the Private Endpoint

On the VM:

```bash
nslookup <storage-account-name>.blob.core.windows.net
```

Expected: a CNAME to `<account>.privatelink.blob.core.windows.net` resolving to **10.0.2.x** (the PE IP), not a public IP.

From your laptop (outside the VNet):

```bash
curl -I https://<storage-account-name>.blob.core.windows.net/web/index.html
```

Expected: **403** (`PublicNetworkAccess` is disabled). Storage is only reachable privately.

---

# The Proof: Private Endpoint ignores NSG by default, but can be made to follow it

Open two terminals: one SSH'd into the VM, one with Azure CLI and the variables from Step 1.

### Test 0 — Check the current setting

```bash
az network vnet subnet show -g $RG --vnet-name $VNET -n snet-pe \
  --query privateEndpointNetworkPolicies -o tsv
```

Expected: `Disabled`

### Test 1 — Baseline: access works

On the VM:

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

Expected: `SUCCESS` and `succeeded!` from `nc`.

### Test 2 — Add a DENY rule on the PE subnet's NSG

```bash
az network nsg rule create -g $RG --nsg-name nsg-pe -n Deny-VM-to-PE-443 \
  --priority 100 --direction Inbound --access Deny --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-address-prefixes 10.0.2.0/24 \
  --destination-port-ranges 443
```

Priority 100 is evaluated before the default `AllowVnetInBound` (65000), so on a normal VM NIC this would block the traffic.

Wait about 1 minute, then on the VM:

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

**Expected: still `SUCCESS`.**

✅ **Proof part 1:** the deny rule exists and is attached to the subnet, but the Private Endpoint ignores it. With `privateEndpointNetworkPolicies = Disabled`, NSGs are not enforced on Private Endpoints.

### Test 3 — Enable Private Endpoint Network Policies

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
  --private-endpoint-network-policies Enabled
```

Values you can use:

| Value | Effect |
|---|---|
| `Disabled` | NSG and UDR are not applied to Private Endpoints (default) |
| `NetworkSecurityGroupEnabled` | Only NSG is applied |
| `RouteTableEnabled` | Only UDR is applied |
| `Enabled` | Both NSG and UDR are applied |

Wait **2–5 minutes** for it to apply, then on the VM:

```bash
sudo /usr/local/bin/sync-index.sh
nc -vz -w 5 <PE_IP> 443
```

**Expected: `FAILED` and `nc` times out.**

✅ **Proof part 2:** the same NSG rule, with no changes, now blocks the traffic. The Private Endpoint follows the NSG once network policies are enabled.

The website on port 80 keeps serving the last downloaded copy, but new syncs fail.

### Test 4 — Show the NSG is the cause (remove the rule)

```bash
az network nsg rule delete -g $RG --nsg-name nsg-pe -n Deny-VM-to-PE-443
```

Wait about 1 minute, then on the VM:

```bash
sudo /usr/local/bin/sync-index.sh
```

**Expected: `SUCCESS` again.** Policies are still `Enabled`, so the default `AllowVnetInBound` rule is now what allows the traffic.

### Test 5 (optional) — Toggle back to Disabled with the deny rule present

Re-create the deny rule from Test 2, confirm it blocks, then:

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n snet-pe \
  --private-endpoint-network-policies Disabled
```

After a few minutes, `sync-index.sh` succeeds again even though the deny rule is still there. This confirms the toggle is the only thing deciding whether the NSG applies.

### Results summary

| Test | PE network policies | Deny rule on nsg-pe | Result |
|---|---|---|---|
| 1 | Disabled | No | ✅ Access works |
| 2 | Disabled | Yes | ✅ Access works → **NSG ignored** |
| 3 | Enabled | Yes | ❌ Blocked → **NSG enforced** |
| 4 | Enabled | No | ✅ Access works (default allow) |
| 5 | Disabled | Yes | ✅ Access works → NSG ignored again |

### Notes and tips

- **The source-side NSG always applies.** An outbound deny on `nsg-vm` (VM subnet) blocks traffic to the PE no matter what the PE subnet setting is. The policy toggle only affects the NSG on the **Private Endpoint's** side.
- Test with **new** connections. An already-open TCP session can survive a rule change for a short time.
- Policy changes on the subnet are not instant; allow a few minutes before testing.
- To keep things simple for troubleshooting, use the PE IP directly with `nc`, as well as the hostname.

---

## Cleanup

```bash
az group delete -n $RG --yes --no-wait
```
