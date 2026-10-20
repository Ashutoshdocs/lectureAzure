# Azure Private DNS Zone + Internal Load Balancer across Peered VNets (Demo)

This demo builds a private web service in one VNet, puts it behind an Azure **Internal Load Balancer (ILB)**, and lets a VM in a **second, peered VNet** reach it by a friendly name such as `web.demo.internal` using an **Azure Private DNS Zone**. The last section adds **auto-registration**.

---

## 1. Architecture

```
                      Private DNS Zone: demo.internal
                      ┌───────────────────────────────────────────┐
                      │ web       A  10.1.1.100   (manual record) │
                      │ vm-web-1  A  10.1.1.x     (auto, Step 9)  │
                      │ vm-web-2  A  10.1.1.y     (auto, Step 9)  │
                      └───────────┬─────────────────────┬─────────┘
                  VNet link (resolution)        VNet link (auto-registration, Step 9)
                                  │                     │
┌─────────────────────────────────┴───┐      ┌──────────┴────────────────────────────────┐
│ vnet-spoke 10.2.0.0/16              │      │ vnet-hub 10.1.0.0/16                       │
│  snet-client 10.2.1.0/24            │      │  snet-web 10.1.1.0/24                      │
│                                     │      │                                            │
│   vm-client                         │◄────►│   ilb-web (frontend 10.1.1.100 : 80)       │
│   curl http://web.demo.internal ────┼──────┼──►      │                                   │
│                                     │ VNet │    ┌────┴─────┐                             │
│                                     │peering    ▼          ▼                             │
│                                     │      │  vm-web-1   vm-web-2   (nginx, backend pool)│
└─────────────────────────────────────┘      │  NAT Gateway (outbound for apt install)    │
                                             └────────────────────────────────────────────┘
```

### Request flow

1. `vm-client` asks Azure DNS (`168.63.129.16`) for `web.demo.internal`.
2. Because `vnet-spoke` is **linked** to the private zone, Azure DNS answers `10.1.1.100` (the ILB frontend).
3. Traffic to `10.1.1.100` crosses the **VNet peering** into `vnet-hub`.
4. The ILB checks the health probe and forwards the request to `vm-web-1` or `vm-web-2`.
5. nginx replies with its own hostname, so you can see the load balancing.

> **Peering and DNS are independent.** The VNet link lets the spoke *resolve* the name. Peering lets the spoke *reach* the IP. You need both.

---

## 2. Prerequisites

- An Azure subscription and Azure CLI 2.60+ (`az login` done)
- A Bash shell (Cloud Shell works)

---

## 3. Variables

```bash
RG=rg-privdns-demo
LOC=centralindia

HUB_VNET=vnet-hub        ; HUB_PREFIX=10.1.0.0/16 ; WEB_SUBNET=snet-web    ; WEB_PREFIX=10.1.1.0/24
SPOKE_VNET=vnet-spoke    ; SPOKE_PREFIX=10.2.0.0/16 ; CLIENT_SUBNET=snet-client ; CLIENT_PREFIX=10.2.1.0/24

LB=ilb-web
LB_IP=10.1.1.100
ZONE=demo.internal
ADMIN=azureuser

az group create -n $RG -l $LOC
```

---

## 4. Step 1 — Hub VNet with outbound access

```bash
az network vnet create -g $RG -n $HUB_VNET \
  --address-prefixes $HUB_PREFIX \
  --subnet-name $WEB_SUBNET --subnet-prefixes $WEB_PREFIX
```

The backend VMs have no public IPs, and new VNets no longer get default outbound internet access. A NAT Gateway lets them download nginx.

```bash
az network public-ip create -g $RG -n pip-natgw --sku Standard
az network nat gateway create -g $RG -n natgw-web --public-ip-addresses pip-natgw
az network vnet subnet update -g $RG --vnet-name $HUB_VNET -n $WEB_SUBNET --nat-gateway natgw-web
```

---

## 5. Step 2 — Two nginx backend VMs

Create `cloud-init.yaml`:

```yaml
#cloud-config
package_update: true
packages:
  - nginx
runcmd:
  - echo "Hello from $(hostname)" > /var/www/html/index.html
  - systemctl enable --now nginx
```

Create the VMs (no public IP):

```bash
for i in 1 2; do
  az vm create -g $RG -n vm-web-$i \
    --image Ubuntu2204 --size Standard_B1s \
    --vnet-name $HUB_VNET --subnet $WEB_SUBNET \
    --public-ip-address "" --nsg-rule NONE \
    --admin-username $ADMIN --generate-ssh-keys \
    --custom-data cloud-init.yaml
done
```

> The NSG created by `az vm create` keeps the default rules, which allow inbound traffic from `VirtualNetwork` (this includes peered VNets) and from `AzureLoadBalancer` (health probes). No extra rule is needed for port 80 in this demo.

---

## 6. Step 3 — Internal Load Balancer

```bash
# Standard ILB with a static private frontend IP
az network lb create -g $RG -n $LB --sku Standard \
  --vnet-name $HUB_VNET --subnet $WEB_SUBNET \
  --frontend-ip-name fe-web --private-ip-address $LB_IP \
  --backend-pool-name bp-web

# Health probe
az network lb probe create -g $RG --lb-name $LB -n probe-http \
  --protocol Http --port 80 --path /

# Load-balancing rule
az network lb rule create -g $RG --lb-name $LB -n rule-http \
  --protocol Tcp --frontend-port 80 --backend-port 80 \
  --frontend-ip-name fe-web --backend-pool-name bp-web --probe-name probe-http

# Add both VM NICs to the backend pool
for i in 1 2; do
  az network nic ip-config address-pool add -g $RG \
    --nic-name vm-web-${i}VMNic --ip-config-name ipconfigvm-web-$i \
    --lb-name $LB --address-pool bp-web
done
```

---

## 7. Step 4 — Spoke VNet and client VM

```bash
az network vnet create -g $RG -n $SPOKE_VNET \
  --address-prefixes $SPOKE_PREFIX \
  --subnet-name $CLIENT_SUBNET --subnet-prefixes $CLIENT_PREFIX

# Client VM with a public IP so you can SSH in for testing
# (use Azure Bastion instead in real environments)
az vm create -g $RG -n vm-client \
  --image Ubuntu2204 --size Standard_B1s \
  --vnet-name $SPOKE_VNET --subnet $CLIENT_SUBNET \
  --public-ip-sku Standard \
  --admin-username $ADMIN --generate-ssh-keys
```

---

## 8. Step 5 — VNet peering (both directions)

Peering must be created on **each** side.

```bash
az network vnet peering create -g $RG -n hub-to-spoke \
  --vnet-name $HUB_VNET --remote-vnet $SPOKE_VNET --allow-vnet-access

az network vnet peering create -g $RG -n spoke-to-hub \
  --vnet-name $SPOKE_VNET --remote-vnet $HUB_VNET --allow-vnet-access

# Both should show "Connected"
az network vnet peering list -g $RG --vnet-name $HUB_VNET --query "[].peeringState" -o tsv
```

---

## 9. Step 6 — Private DNS zone and A record

```bash
az network private-dns zone create -g $RG -n $ZONE

# web.demo.internal -> ILB frontend
az network private-dns record-set a add-record -g $RG \
  -z $ZONE -n web -a $LB_IP
```

---

## 10. Step 7 — Link the spoke VNet to the zone

```bash
az network private-dns link vnet create -g $RG \
  -z $ZONE -n link-spoke \
  -v $SPOKE_VNET --registration-enabled false
```

`--registration-enabled false` means this is a **resolution-only** link: VMs in the spoke can look up names in the zone, but their own names are not added to it.

---

## 11. Step 8 — Test from the client VM

```bash
CLIENT_IP=$(az vm show -d -g $RG -n vm-client --query publicIps -o tsv)
ssh $ADMIN@$CLIENT_IP
```

Inside `vm-client`:

```bash
# 1. Name resolves to the ILB frontend
getent hosts web.demo.internal
# 10.1.1.100      web.demo.internal

# 2. Requests go through the ILB to both backends
for i in $(seq 1 10); do curl -s http://web.demo.internal; done
# Hello from vm-web-1
# Hello from vm-web-2
# Hello from vm-web-1
# ...
```

The ILB distributes by a hash of source/destination IP and port, so you'll usually see both VMs but not a strict alternation. Stop nginx on one VM (`sudo systemctl stop nginx`) and all traffic will move to the other once the probe fails.

---

## 12. Step 9 — Auto-registration (add-on)

### What it does

When a VNet is linked to a private DNS zone **with auto-registration enabled**, Azure automatically maintains an **A record for every VM** in that VNet:

| Event | What happens in the zone |
|---|---|
| VM created in the VNet | A record `<vm-name>.<zone>` → VM's private IP is added |
| VM's private IP changes | Record is updated |
| VM deleted | Record is removed |

So you never have to create or clean up DNS records for VMs by hand.

### Key rules

- A registration link also provides **resolution** for that VNet.
- A VNet can have auto-registration enabled to **only one** private DNS zone (it can still have resolution links to many zones).
- Only **VMs' NIC IPs** are registered. Load balancer frontends, private endpoints, and other resources are **not** — that's why `web` stays a manual record.
- Auto-registered records are managed by Azure; you can't edit them manually.

### Enable it on the hub VNet

```bash
az network private-dns link vnet create -g $RG \
  -z $ZONE -n link-hub \
  -v $HUB_VNET --registration-enabled true
```

Check the records after a minute:

```bash
az network private-dns record-set a list -g $RG -z $ZONE \
  --query "[].{name:name, ip:aRecords[0].ipv4Address, auto:isAutoRegistered}" -o table
```

```
Name      Ip          Auto
--------  ----------  ------
web       10.1.1.100  False
vm-web-1  10.1.1.4    True
vm-web-2  10.1.1.5    True
```

### Test from the client VM

```bash
curl -s http://vm-web-1.demo.internal   # Hello from vm-web-1 (direct, bypasses the ILB)
curl -s http://vm-web-2.demo.internal   # Hello from vm-web-2
curl -s http://web.demo.internal        # via the ILB
```

Now add a third VM (`vm-web-3`) to `snet-web`: its record appears automatically. Delete it and the record disappears.

> **Tip:** use `web.demo.internal` (the ILB) for application traffic, and the per-VM names for admin tasks or troubleshooting a single backend.

---

## 13. Troubleshooting

| Symptom | Check |
|---|---|
| Name doesn't resolve | Is the client's VNet linked to the zone? Is the VNet using Azure-provided DNS (not custom DNS servers)? |
| Resolves but curl times out | Peering state `Connected` on both sides? NSG blocking port 80? |
| ILB returns nothing | Backend probe healthy? `curl localhost` on each backend VM; check `az network lb show` backend pool membership |
| nginx not installed | Backend subnet needs outbound access (NAT Gateway); check `/var/log/cloud-init-output.log` |

---

## 14. Cleanup

```bash
az group delete -n $RG --yes --no-wait
```
