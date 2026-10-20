# Azure NAT Gateway — End-to-End Demo (Linux VMs)

This demo shows **why** Azure NAT Gateway exists and **how** to use it. You'll see private Linux VMs with **no internet access**. Then you'll attach a NAT Gateway and watch them all reach the internet through **one static public IP** while staying unreachable from the internet.

---

## 1. Why NAT Gateway?

VMs in a private subnet (no public IP) often still need **outbound** internet access. For example, they may need to:

- run `apt update` / install packages
- pull container images, call external APIs or SaaS endpoints
- send logs/metrics to external services

### Ways a VM can reach the internet

| Option | Problem |
|---|---|
| **Public IP on every VM** | Every VM is exposed inbound; many IPs to manage and allowlist |
| **Default outbound access** (implicit Azure IP) | Being retired. New VNets default to private subnets with no implicit outbound; the IP isn't yours and can change |
| **Load Balancer outbound rules** | Works, but you must manually allocate SNAT ports per VM; port exhaustion is common |
| **NAT Gateway** ✅ | Outbound-only, static IP(s), SNAT ports allocated on demand, no per-VM config |

### What NAT Gateway gives you

- **Outbound only.** Unsolicited inbound connections from the internet are **not** possible through it. Return traffic for connections the VM started is allowed.
- **Predictable egress IP.** All VMs in the subnet leave via the same static public IP(s), so you can give one IP to partners/firewalls for **allowlisting**.
- **Scale.** Each public IP provides 64,512 SNAT ports. Up to 16 IPs can be attached, and ports are shared dynamically across all VMs in the subnet. This greatly reduces SNAT port exhaustion.
- **Zero VM config.** It's attached to the **subnet**; every VM in the subnet uses it automatically.
- **Precedence.** For outbound traffic, a NAT Gateway on the subnet takes priority over a VM's own public IP and over Load Balancer outbound rules. Inbound via a VM's public IP or a load balancer still works.

---

## 2. Architecture

```
                         Internet
                            ▲   (outbound only)
                            │
                  ┌─────────┴──────────┐
                  │  pip-natgw          │  static public IP (e.g. 20.x.x.x)
                  │  natgw-demo         │
                  └─────────┬──────────┘
                            │ associated to subnet
┌───────────────────────────┼────────────────────────────────────────┐
│ vnet-nat-demo 10.10.0.0/16│                                        │
│                           │                                        │
│  snet-private 10.10.1.0/24 (no public IPs)                         │
│   ┌──────────┐   ┌──────────┐                                      │
│   │ vm-app-1 │   │ vm-app-2 │   both egress as 20.x.x.x            │
│   └────▲─────┘   └────▲─────┘                                      │
│        │ SSH (private) │                                           │
│  snet-jump 10.10.2.0/24                                            │
│   ┌────┴───────────────┴┐                                          │
│   │ vm-jump (public IP) │◄──── SSH from your laptop                │
│   └─────────────────────┘                                          │
└────────────────────────────────────────────────────────────────────┘
```

- `vm-app-1`, `vm-app-2`: Ubuntu, **no public IP**. These represent your app servers.
- `vm-jump`: Ubuntu **with** a public IP, used only to SSH into the private VMs. Azure Bastion is the production alternative.

---

## 3. Prerequisites

- Azure subscription, Azure CLI 2.60+, `az login` done
- Bash shell (Cloud Shell works)
- An SSH key at `~/.ssh/id_rsa` (or let `--generate-ssh-keys` create one)

---

## 4. Variables

```bash
RG=rg-natgw-demo
LOC=centralindia
VNET=vnet-nat-demo
PRIV_SUBNET=snet-private
JUMP_SUBNET=snet-jump
NATGW=natgw-demo
NAT_PIP=pip-natgw
ADMIN=azureuser

az group create -n $RG -l $LOC
```

---

## 5. Step 1 — VNet with private subnets

`--default-outbound false` makes the subnets **private**: VMs get no implicit internet access. This matches how new VNets behave going forward.

```bash
az network vnet create -g $RG -n $VNET --address-prefixes 10.10.0.0/16

az network vnet subnet create -g $RG --vnet-name $VNET -n $PRIV_SUBNET \
  --address-prefixes 10.10.1.0/24 --default-outbound false

az network vnet subnet create -g $RG --vnet-name $VNET -n $JUMP_SUBNET \
  --address-prefixes 10.10.2.0/24 --default-outbound false
```

---

## 6. Step 2 — Create the Linux VMs

### Private app VMs (no public IP)

```bash
for i in 1 2; do
  az vm create -g $RG -n vm-app-$i \
    --image Ubuntu2204 --size Standard_B1s \
    --vnet-name $VNET --subnet $PRIV_SUBNET \
    --public-ip-address "" \
    --admin-username $ADMIN --generate-ssh-keys
done
```

### Jump box (public IP, for SSH only)

```bash
az vm create -g $RG -n vm-jump \
  --image Ubuntu2204 --size Standard_B1s \
  --vnet-name $VNET --subnet $JUMP_SUBNET \
  --public-ip-sku Standard \
  --admin-username $ADMIN --generate-ssh-keys

JUMP_IP=$(az vm show -d -g $RG -n vm-jump --query publicIps -o tsv)
APP1_IP=$(az vm show -d -g $RG -n vm-app-1 --query privateIps -o tsv)
APP2_IP=$(az vm show -d -g $RG -n vm-app-2 --query privateIps -o tsv)
echo "jump=$JUMP_IP app1=$APP1_IP app2=$APP2_IP"
```

> The default NSG from `az vm create` allows SSH (22) on the jump box. Restrict it to your own IP in anything beyond a demo.

---

## 7. Step 3 — Prove there is NO outbound access (before)

SSH into a private VM **through the jump box** (`-J` = ProxyJump):

```bash
ssh -J $ADMIN@$JUMP_IP $ADMIN@$APP1_IP
```

Inside `vm-app-1`:

```bash
curl -s --max-time 10 https://ifconfig.me || echo "NO OUTBOUND ACCESS"
# NO OUTBOUND ACCESS

sudo apt-get update
# Fails / hangs: cannot reach archive.ubuntu.com
exit
```

Optional: you can run the same check without SSH:

```bash
az vm run-command invoke -g $RG -n vm-app-1 --command-id RunShellScript \
  --scripts "curl -s --max-time 10 https://ifconfig.me || echo NO_OUTBOUND" \
  --query "value[0].message" -o tsv
```

Also note the jump box's own egress IP. It has a public IP, so it goes out through that IP:

```bash
ssh $ADMIN@$JUMP_IP "curl -s https://ifconfig.me; echo"
# prints the same IP as $JUMP_IP
```

---

## 8. Step 4 — Create the NAT Gateway

```bash
# 1. Static Standard public IP for egress
az network public-ip create -g $RG -n $NAT_PIP \
  --sku Standard --allocation-method Static

# 2. NAT Gateway (idle timeout in minutes: 4–120, default 4)
az network nat gateway create -g $RG -n $NATGW \
  --public-ip-addresses $NAT_PIP \
  --idle-timeout 10

NAT_IP=$(az network public-ip show -g $RG -n $NAT_PIP --query ipAddress -o tsv)
echo "NAT egress IP: $NAT_IP"
```

> **Zones:** a NAT Gateway can be pinned to an availability zone with `--zone 1` (its public IP must be in the same zone). Without `--zone`, Azure places it as a non-zonal resource.

---

## 9. Step 5 — Attach it to the private subnet

This is the only step that "turns it on". There are no changes on the VMs themselves.

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n $PRIV_SUBNET \
  --nat-gateway $NATGW

# Verify
az network vnet subnet show -g $RG --vnet-name $VNET -n $PRIV_SUBNET \
  --query natGateway.id -o tsv
```

---

## 10. Step 6 — Prove outbound works (after)

```bash
for vm in $APP1_IP $APP2_IP; do
  echo -n "$vm egress IP: "
  ssh -J $ADMIN@$JUMP_IP $ADMIN@$vm "curl -s https://ifconfig.me"; echo
done
echo "Expected NAT IP: $NAT_IP"
```

```
10.10.1.4 egress IP: 20.x.x.x
10.10.1.5 egress IP: 20.x.x.x
Expected NAT IP: 20.x.x.x
```

**Both VMs share the same static egress IP**, which is the NAT Gateway's IP.

Now do real work from a private VM:

```bash
ssh -J $ADMIN@$JUMP_IP $ADMIN@$APP1_IP
sudo apt-get update && sudo apt-get install -y nginx   # works now
curl -I https://www.microsoft.com                     # works now
exit
```

---

## 11. Step 7 — Prove it is outbound-only

The NAT IP does **not** accept inbound connections. From your laptop:

```bash
curl --max-time 10 http://$NAT_IP   # times out
ssh -o ConnectTimeout=10 $ADMIN@$NAT_IP   # times out
```

Even though nginx is now running on `vm-app-1`, nothing on the internet can reach it through the NAT Gateway.

---

## 12. Step 8 (optional) — NAT Gateway takes precedence over a VM public IP

Attach the NAT Gateway to the **jump** subnet too:

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n $JUMP_SUBNET \
  --nat-gateway $NATGW

ssh $ADMIN@$JUMP_IP "curl -s https://ifconfig.me; echo"
# now prints $NAT_IP, not $JUMP_IP
```

- **Outbound** from `vm-jump` now uses the NAT IP.
- **Inbound** SSH to `vm-jump` via its own public IP still works, because you just used it.

Revert if you like:

```bash
az network vnet subnet update -g $RG --vnet-name $VNET -n $JUMP_SUBNET --remove natGateway
```

---

## 13. Scaling egress: more IPs or a prefix

If you have many VMs making lots of connections to the same destination, add more IPs for more SNAT ports (64,512 per IP, up to 16 IPs):

```bash
az network public-ip create -g $RG -n pip-natgw-2 --sku Standard --allocation-method Static
az network nat gateway update -g $RG -n $NATGW --public-ip-addresses $NAT_PIP pip-natgw-2
```

Or use a **public IP prefix** so partners can allowlist one contiguous range:

```bash
az network public-ip prefix create -g $RG -n pipfx-natgw --length 31
az network nat gateway update -g $RG -n $NATGW --public-ip-prefixes pipfx-natgw
```

---

## 14. Monitoring

Useful NAT Gateway metrics in Azure Monitor:

| Metric | What it tells you |
|---|---|
| `SNATConnectionCount` | New SNAT connections (by state, e.g. attempted / failed) |
| `TotalConnectionCount` | Active SNAT connections; watch it against your port capacity |
| `DroppedPackets` | Packets dropped by the NAT Gateway |
| `DatapathAvailability` | Health of the NAT Gateway data path |
| `ByteCount` / `PacketCount` | Traffic volume |

```bash
NATGW_ID=$(az network nat gateway show -g $RG -n $NATGW --query id -o tsv)
az monitor metrics list --resource $NATGW_ID --metric TotalConnectionCount \
  --interval PT5M -o table
```

---

## 15. Key facts and limits

- Attached per **subnet**. One subnet can use one NAT Gateway; one NAT Gateway can serve multiple subnets **in the same VNet**.
- Requires **Standard** SKU public IPs / prefixes (not Basic).
- Outbound **TCP and UDP** only. ICMP (ping) to the internet does **not** go through NAT Gateway, so test with `curl`, not `ping`.
- No inbound internet connections through NAT Gateway; use a public load balancer, Application Gateway, or a VM public IP for inbound.
- Pricing has two parts: an hourly charge for the gateway **plus** a per-GB data processed charge. Check current pricing for your region.

---

## 16. Troubleshooting

| Symptom | Check |
|---|---|
| Still no outbound after attaching | Is the NAT Gateway attached to the **VM's** subnet? `az network vnet subnet show ... --query natGateway` |
| `ping 8.8.8.8` fails | Expected; ICMP isn't supported. Use `curl` |
| Outbound blocked | NSG outbound rules or a route table (UDR) sending `0.0.0.0/0` to a firewall/NVA overrides the path |
| Intermittent connection failures at high load | SNAT exhaustion; check `SNATConnectionCount` failed state, add public IPs, reuse connections |
| Egress IP isn't the NAT IP | Traffic may be going via a UDR to a firewall, or the VM is in a different subnet |

---

## 17. Cleanup

```bash
az group delete -n $RG --yes --no-wait
```
